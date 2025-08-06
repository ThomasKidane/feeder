//
//  swift_command_bridge.h
//  feeder
//
//  Command-line bridge to working Swift code
//

#ifndef SWIFT_COMMAND_BRIDGE_H
#define SWIFT_COMMAND_BRIDGE_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QProcess>

class SwiftCommandBridge : public QObject {
    Q_OBJECT
    
public:
    explicit SwiftCommandBridge(QObject *parent = nullptr);
    ~SwiftCommandBridge();
    
    // Device management
    void startDeviceDiscovery();
    void stopDeviceDiscovery();
    QStringList getDiscoveredDevices();
    bool selectDevice(const QString &deviceName);
    
    // File management
    QStringList getDeviceFiles();
    
    // Download operations
    bool downloadSelectedFiles(const QStringList &selectedFiles, 
                             const QString &outputDirectory,
                             const QString &fileNamePrefix);
    bool downloadAllFiles(const QString &outputDirectory,
                         const QString &fileNamePrefix);
    
signals:
    void deviceConnected(const QString &deviceName);
    void deviceDisconnected(const QString &deviceName);
    void fileListReady(const QStringList &fileList);
    void downloadProgress(const QString &filename, int progress);
    void downloadComplete(const QString &filename, bool success);
    
private:
    QProcess *swiftProcess_;
    QString swiftAppPath_;
    
    void setupSwiftProcess();
    bool executeSwiftCommand(const QStringList &arguments, QString &output);
};

#endif // SWIFT_COMMAND_BRIDGE_H 