#pragma once
#include <QObject>
#include <QString>
#include <QStringList>
#include <QImage>
#include <QDateTime>
#include <memory>

// Forward declaration of Swift framework wrapper
class FeederCoreWrapper;

struct DeviceFileInfo {
    QString filename;
    qint64 size;
    QDateTime date;
    QString type;
    QImage thumbnail;
};
Q_DECLARE_METATYPE(DeviceFileInfo)

class DeviceController : public QObject {
    Q_OBJECT
public:
    explicit DeviceController(QObject *parent = nullptr);
    ~DeviceController();

    void startMonitoring();
    void stopMonitoring();
    void refreshFiles();
    void downloadSelectedFiles(const QStringList &selectedFiles, const QString &outputDirectory);
    void downloadAllFiles(const QString &outputDirectory);

signals:
    void deviceConnected(const QString &deviceName);
    void deviceDisconnected(const QString &deviceName);
    void fileListReady(const QList<DeviceFileInfo> &fileList);
    void fileDownloaded(const QString &filename, const QString &outputPath);
    void fileDownloadError(const QString &filename, const QString &error);

private:
    std::unique_ptr<FeederCoreWrapper> swiftCore_;
    QTimer *discoveryTimer_;
    
    void refreshDeviceList();
    void refreshFileList();
}; 