#ifndef SWIFT_WRAPPER_H
#define SWIFT_WRAPPER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QProcess>

class SwiftWrapper : public QObject {
    Q_OBJECT
    
public:
    explicit SwiftWrapper(QObject *parent = nullptr);
    ~SwiftWrapper();
    
    // Device management
    void startDeviceDiscovery();
    QStringList getDiscoveredDevices();
    bool selectDevice(const QString &deviceName);
    
    // File operations
    QStringList getDeviceFiles();
    QStringList getDeviceFileSizes();
    QStringList getDeviceFileDates();
    bool downloadSelectedFiles(const QStringList &selectedFiles, 
                             const QString &outputDirectory,
                             const QString &fileNamePrefix);
    bool downloadAllFiles(const QString &outputDirectory,
                         const QString &fileNamePrefix);
    
    // Status
    bool isDeviceConnected();
    QString getSelectedDeviceName();
    
signals:
    void deviceConnected(const QString &deviceName);
    void deviceDisconnected(const QString &deviceName);
    void fileListReady(const QStringList &fileList, const QStringList &sizeList, const QStringList &dateList);
    void downloadProgress(const QString &filename, int progress);
    void downloadComplete(const QString &filename, bool success);
    
private:
    QString swiftAppPath;
    QString currentDevice;
    QStringList cachedFiles;
    QStringList cachedSizes;
    QStringList cachedDates;
    
    bool runSwiftCommand(const QStringList &args, QString &output);
    void parseFileList(const QString &output);
};

#endif // SWIFT_WRAPPER_H 