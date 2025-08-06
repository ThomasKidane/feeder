//
//  simple_swift_bridge.h
//  feeder
//
//  Simple bridge for working Swift code
//

#ifndef SIMPLE_SWIFT_BRIDGE_H
#define SIMPLE_SWIFT_BRIDGE_H

#include <QObject>
#include <QString>
#include <QStringList>

class SimpleSwiftBridge : public QObject {
    Q_OBJECT
    
public:
    explicit SimpleSwiftBridge(QObject *parent = nullptr);
    ~SimpleSwiftBridge();
    
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
    void* swiftBridge_;
};

#endif // SIMPLE_SWIFT_BRIDGE_H 