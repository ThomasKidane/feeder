#include "swift_wrapper.h"
#include <QDir>
#include <QDebug>

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
    qDebug() << "SwiftWrapper: Starting device discovery";
    
    // Run the full workflow in one call
    QString output;
    if (runSwiftCommand(QStringList() << "full", output)) {
        qDebug() << "SwiftWrapper: Full workflow completed";
        
        // Parse the output to extract files and sizes
        parseFileList(output);
        
        if (!cachedFiles.isEmpty()) {
            emit fileListReady(cachedFiles, cachedSizes, cachedDates);
            qDebug() << "SwiftWrapper: Emitted" << cachedFiles.size() << "files";
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
    qDebug() << "SwiftWrapper: Selecting device:" << deviceName;
    
    QString output;
    if (runSwiftCommand(QStringList() << "select" << deviceName, output)) {
        currentDevice = deviceName;
        qDebug() << "SwiftWrapper: Device selected successfully";
        
        // Get files after device selection
        QStringList files = getDeviceFiles();
        QStringList sizes = getDeviceFileSizes();
        QStringList dates = getDeviceFileDates();
        
        if (!files.isEmpty()) {
            emit fileListReady(files, sizes, dates);
        }
        
        return true;
    }
    
    qDebug() << "SwiftWrapper: Failed to select device";
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
    
    qDebug() << "SwiftWrapper: Parsed" << cachedFiles.size() << "files," << cachedSizes.size() << "sizes, and" << cachedDates.size() << "dates";
}

bool SwiftWrapper::downloadSelectedFiles(const QStringList &selectedFiles, 
                                       const QString &outputDirectory,
                                       const QString &fileNamePrefix) {
    qDebug() << "SwiftWrapper: Downloading" << selectedFiles.size() << "files to" << outputDirectory;
    qDebug() << "SwiftWrapper: Selected files:" << selectedFiles;
    
    // First, we need to make sure a device is selected and files are available
    if (cachedFiles.isEmpty()) {
        qDebug() << "SwiftWrapper: No files available, running full workflow first";
        QString output;
        if (!runSwiftCommand(QStringList() << "full", output)) {
            qDebug() << "SwiftWrapper: Failed to get files";
            return false;
        }
        parseFileList(output);
    }
    
    // Now run the download command
    QStringList args;
    args << "download" << outputDirectory << fileNamePrefix;
    args.append(selectedFiles);
    
    qDebug() << "SwiftWrapper: Running download command with args:" << args;
    
    QString output;
    if (runSwiftCommand(args, output)) {
        qDebug() << "SwiftWrapper: Download initiated successfully";
        return true;
    }
    
    qDebug() << "SwiftWrapper: Download failed - see error output above";
    return false;
}

bool SwiftWrapper::downloadAllFiles(const QString &outputDirectory,
                                   const QString &fileNamePrefix) {
    qDebug() << "SwiftWrapper: Downloading all files to" << outputDirectory;
    
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