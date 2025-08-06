//
//  swift_device_controller.h
//  feeder
//
//  Objective-C++ bridge for Swift integration
//

#ifndef SWIFT_DEVICE_CONTROLLER_H
#define SWIFT_DEVICE_CONTROLLER_H

#include <QObject>
#include <QString>
#include <QStringList>
#include <QList>

// Forward declaration
class SwiftDeviceControllerPrivate;

class SwiftDeviceController : public QObject {
    Q_OBJECT
    
public:
    explicit SwiftDeviceController(QObject *parent = nullptr);
    ~SwiftDeviceController();
    
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
            void fileListReady(const QStringList &fileList, const QStringList &sizeList);
            void downloadProgress(const QString &filename, int progress);
            void downloadComplete(const QString &filename, bool success);
    
private:
    SwiftDeviceControllerPrivate *d;
};

#endif // SWIFT_DEVICE_CONTROLLER_H 