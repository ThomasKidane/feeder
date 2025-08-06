#include "swift_wrapper.h"
#include <QDir>
#include <QDebug>
#include <QFileInfo>
#include <QFile>
#include <QThread>

SwiftWrapper::SwiftWrapper(QObject *parent) : QObject(parent) {
    // Set path to the Swift app
    swiftAppPath = "/Users/thomaskidane/Documents/Projects/FeederSwiftApp/FeederSwiftApp.swift";
}

SwiftWrapper::~SwiftWrapper() {
}

bool SwiftWrapper::runSwiftCommand(const QStringList &args, QString &output) {
    QProcess process;
    process.setProgram("swift");
    process.setArguments(QStringList() << swiftAppPath << args);
    
    qDebug() << "SwiftWrapper: Running command: swift" << swiftAppPath << args;
    
    process.start();
    if (!process.waitForFinished(30000)) { // 30 second timeout
        qDebug() << "SwiftWrapper: Swift command timed out";
        return false;
    }
    
    output = QString::fromUtf8(process.readAllStandardOutput());
    QString error = QString::fromUtf8(process.readAllStandardError());
    
    qDebug() << "SwiftWrapper: Exit code:" << process.exitCode();
    qDebug() << "SwiftWrapper: Output:" << output;
    
    if (!error.isEmpty()) {
        qDebug() << "SwiftWrapper: Error output:" << error;
    }
    
    bool success = process.exitCode() == 0;
    qDebug() << "SwiftWrapper: Command" << (success ? "succeeded" : "failed");
    
    return success;
}

void SwiftWrapper::startDeviceDiscovery() {
    // Run the full workflow in one call
    QString output;
    if (runSwiftCommand(QStringList() << "full", output)) {
        // Parse the output to extract files and sizes
        parseFileList(output);
        
        if (!cachedFiles.isEmpty()) {
            emit fileListReady(cachedFiles, cachedSizes, cachedDates);
        }
    }
}

QStringList SwiftWrapper::getDiscoveredDevices() {
    QString output;
    QStringList devices;
    
    if (runSwiftCommand(QStringList() << "list", output)) {
        // Parse the output to extract device names
        // Expected format: "Discovered devices: ["device1", "device2"]"
        if (output.contains("Discovered devices:")) {
            QString devicesStr = output.split("Discovered devices:").last().trimmed();
            if (devicesStr.startsWith("[") && devicesStr.endsWith("]")) {
                devicesStr = devicesStr.mid(1, devicesStr.length() - 2);
                QStringList deviceList = devicesStr.split("\", \"");
                for (QString &device : deviceList) {
                    device = device.remove("\"");
                    if (!device.isEmpty()) {
                        devices << device;
                    }
                }
            }
        }
    }
    
    return devices;
}

bool SwiftWrapper::selectDevice(const QString &deviceName) {
    QString output;
    if (runSwiftCommand(QStringList() << "select" << deviceName, output)) {
        currentDevice = deviceName;
        
        // Get files after device selection
        QStringList files = getDeviceFiles();
        QStringList sizes = getDeviceFileSizes();
        QStringList dates = getDeviceFileDates();
        
        if (!files.isEmpty()) {
            emit fileListReady(files, sizes, dates);
        }
        
        return true;
    }
    
    return false;
}

QStringList SwiftWrapper::getDeviceFiles() {
    QString output;
    
    if (runSwiftCommand(QStringList() << "files", output)) {
        parseFileList(output);
    }
    
    return cachedFiles;
}

QStringList SwiftWrapper::getDeviceFileSizes() {
    return cachedSizes;
}

QStringList SwiftWrapper::getDeviceFileDates() {
    return cachedDates;
}

void SwiftWrapper::parseFileList(const QString &output) {
    cachedFiles.clear();
    cachedSizes.clear();
    cachedDates.clear();
    
    // Parse the output to extract files, sizes, and dates from the full workflow
    // Look for lines that contain "FeederSwiftApp: Found file:" followed by filename, size, and date
    
    QStringList lines = output.split('\n');
    
    for (const QString &line : lines) {
        // Look for lines that contain "FeederSwiftApp: Found file:" followed by filename, size, and date
        if (line.contains("FeederSwiftApp: Found file:") && line.contains(" (size: ")) {
            QString trimmedLine = line.trimmed();
            
            // Extract the part after "FeederSwiftApp: Found file:"
            int startPos = trimmedLine.indexOf("FeederSwiftApp: Found file:") + 28; // length of "FeederSwiftApp: Found file:"
            QString filePart = trimmedLine.mid(startPos);
            
            // Extract filename, size, and date
            int sizeStart = filePart.indexOf(" (size: ");
            int sizeEnd = filePart.indexOf(")", sizeStart);
            
            if (sizeStart > 0 && sizeEnd > sizeStart) {
                QString filename = filePart.left(sizeStart);
                QString size = filePart.mid(sizeStart + 8, sizeEnd - sizeStart - 8); // 8 = length of " (size: "
                
                // Check if there's a date part
                QString date = "Unknown";
                int dateStart = filePart.indexOf(", date: ", sizeEnd);
                if (dateStart > 0) {
                    int dateEnd = filePart.indexOf(")", dateStart);
                    if (dateEnd > dateStart) {
                        date = filePart.mid(dateStart + 8, dateEnd - dateStart - 8); // 8 = length of ", date: "
                    }
                }
                
                if (!filename.isEmpty() && !size.isEmpty()) {
                    cachedFiles << filename;
                    cachedSizes << size;
                    cachedDates << date;
                }
            }
        }
    }
    

}

bool SwiftWrapper::downloadSelectedFiles(const QStringList &selectedFiles, 
                                       const QString &outputDirectory,
                                       const QString &fileNamePrefix) {
    // First, we need to make sure a device is selected and files are available
    if (cachedFiles.isEmpty()) {
        QString output;
        if (!runSwiftCommand(QStringList() << "full", output)) {
            return false;
        }
        parseFileList(output);
    }
    
    // Now run the download command
    QStringList args;
    args << "download" << outputDirectory << fileNamePrefix;
    args.append(selectedFiles);
    
    QString output;
    if (runSwiftCommand(args, output)) {
        // Wait a bit for downloads to complete, then convert files
        QThread::msleep(2000); // Wait 2 seconds for downloads to complete
        
        convertDownloadedFiles(outputDirectory);
        
        return true;
    }
    
    return false;
}

bool SwiftWrapper::downloadAllFiles(const QString &outputDirectory,
                                   const QString &fileNamePrefix) {
    // Get all files and download them
    QStringList allFiles = getDeviceFiles();
    return downloadSelectedFiles(allFiles, outputDirectory, fileNamePrefix);
}

bool SwiftWrapper::isDeviceConnected() {
    return !currentDevice.isEmpty();
}

QString SwiftWrapper::getSelectedDeviceName() {
    return currentDevice;
}

bool SwiftWrapper::convertFile(const QString &inputPath, const QString &outputPath) {
    QFileInfo inputFile(inputPath);
    QString inputExt = inputFile.suffix().toLower();
    QString outputExt = QFileInfo(outputPath).suffix().toLower();
    
    QProcess process;
    
    if (inputExt == "heic" && outputExt == "jpg") {
        // Use sips for HEIC to JPG conversion (macOS built-in)
        process.setProgram("/usr/bin/sips");
        process.setArguments(QStringList() 
            << "-s" << "format" << "jpeg"
            << "-s" << "formatOptions" << "high"
            << inputPath
            << "--out" << outputPath);
    } else if (inputExt == "mov" && outputExt == "mp4") {
        // Use FFmpeg for MOV to MP4 conversion
        process.setProgram("/opt/homebrew/bin/ffmpeg");
        process.setArguments(QStringList()
            << "-i" << inputPath
            << "-c:v" << "libx264"
            << "-c:a" << "aac"
            << "-preset" << "medium"
            << "-crf" << "23"
            << "-y"
            << outputPath);
    } else {
        return true;
    }
    
    process.start();
    if (!process.waitForFinished(60000)) { // 60 second timeout
        process.terminate();
        return false;
    }
    
    bool success = process.exitCode() == 0;
    return success;
}

void SwiftWrapper::convertDownloadedFiles(const QString &outputDirectory) {
    QDir dir(outputDirectory);
    if (!dir.exists()) {
        return;
    }
    
    // Look for subdirectories (like Feeder_A01E)
    QStringList subdirs = dir.entryList(QDir::Dirs | QDir::NoDotAndDotDot);
    
    for (const QString &subdir : subdirs) {
        if (subdir.startsWith("Feeder_")) {
            QString subdirPath = dir.absoluteFilePath(subdir);
            QDir subdirDir(subdirPath);
            
            // Get all files in the subdirectory
            QStringList files = subdirDir.entryList(QDir::Files);
            
            for (const QString &file : files) {
                QString filePath = subdirDir.absoluteFilePath(file);
                QFileInfo fileInfo(filePath);
                QString ext = fileInfo.suffix().toLower();
                QString baseName = fileInfo.baseName();
                
                // Convert HEIC to JPG
                if (ext == "heic") {
                    QString outputPath = subdirDir.absoluteFilePath(baseName + ".jpg");
                    
                    if (convertFile(filePath, outputPath)) {
                        // Delete the original HEIC file
                        QFile::remove(filePath);
                    }
                }
                // Convert MOV to MP4
                else if (ext == "mov") {
                    QString outputPath = subdirDir.absoluteFilePath(baseName + ".mp4");
                    
                    if (convertFile(filePath, outputPath)) {
                        // Delete the original MOV file
                        QFile::remove(filePath);
                    }
                }
            }
        }
    }
} 