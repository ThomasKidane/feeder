#include "devicecontroller.h"
#include <QDebug>
#include <QStringList>
#include <QImage>
#include <QDateTime>
#include <objc/runtime.h>

#import <ImageCaptureCore/ImageCaptureCore.h>
#import <Foundation/Foundation.h>
#import <Photos/Photos.h>

@interface DeviceDelegate : NSObject <ICDeviceBrowserDelegate, ICCameraDeviceDelegate, ICCameraDeviceDownloadDelegate>

@property (nonatomic, assign) DeviceController *controller;
@property (nonatomic, strong) ICCameraDevice *lastCameraDevice;
@property (nonatomic, strong) NSMutableArray *pendingDownloads;

- (instancetype)init;

@end

@implementation DeviceDelegate

- (instancetype)init {
    self = [super init];
    if (self) {
        self.pendingDownloads = [NSMutableArray array];
    }
    return self;
}

- (void)deviceBrowser:(ICDeviceBrowser *)browser didAddDevice:(ICDevice *)device moreComing:(BOOL)moreComing {
    qDebug() << "=== DEVICE DEBUG ===";
    qDebug() << "Device detected:" << QString::fromNSString(device.name);
    qDebug() << "Device type:" << (device.type == ICDeviceTypeCamera ? "Camera" : "Other");
    qDebug() << "Device transport type:" << QString::fromNSString(device.transportType);
    qDebug() << "Device USB product ID:" << device.usbProductID;
    qDebug() << "Device USB vendor ID:" << device.usbVendorID;
    
    // Only handle camera devices
    if (device.type == ICDeviceTypeCamera) {
        ICCameraDevice *camera = (ICCameraDevice *)device;
        self.lastCameraDevice = camera;
        camera.delegate = self;
        
        qDebug() << "Requesting device authorization...";
        
        // Emit device connected signal
        if (self.controller) {
            emit self.controller->deviceConnected(QString::fromNSString(device.name));
        }
        
        [camera requestOpenSession];
    }
}

- (void)deviceBrowser:(ICDeviceBrowser *)browser didRemoveDevice:(ICDevice *)device moreGoing:(BOOL)moreGoing {
    qDebug() << "Device removed:" << QString::fromNSString(device.name);
    
    // Emit device disconnected signal
    if (self.controller) {
        emit self.controller->deviceDisconnected(QString::fromNSString(device.name));
    }
}

- (void)didRemoveDevice:(ICDevice *)device {
    // Required protocol method - no-op implementation
}

- (void)device:(ICDevice *)device didOpenSessionWithError:(NSError *)error {
    qDebug() << "=== SESSION DEBUG ===";
    if (error) {
        qDebug() << "Session open error:" << QString::fromNSString(error.localizedDescription);
        qDebug() << "Error code:" << error.code;
        qDebug() << "Error domain:" << QString::fromNSString(error.domain);
        
        // Specific handling for device unlock requirement
        if (error.code == -9943) {
            qDebug() << "*** IMPORTANT: Please unlock your iPhone and trust this computer ***";
            qDebug() << "*** Then tap 'Trust' when the dialog appears on your iPhone ***";
            qDebug() << "*** After unlocking, click 'Refresh' button to retry ***";
            qDebug() << "*** This is required for ImageCaptureCore to work ***";
            
            // Retry after a delay
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3.0 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                qDebug() << "Retrying session open...";
                if ([device isKindOfClass:[ICCameraDevice class]]) {
                    ICCameraDevice *camera = (ICCameraDevice *)device;
                    [camera requestOpenSession];
                }
            });
        }
    } else {
        qDebug() << "Device session opened successfully for:" << QString::fromNSString(device.name);
        
        if ([device isKindOfClass:[ICCameraDevice class]]) {
            ICCameraDevice *camera = (ICCameraDevice *)device;
            self.lastCameraDevice = camera;
            
            // Comprehensive device diagnostics
            qDebug() << "=== DEVICE DIAGNOSTICS ===";
            qDebug() << "Device UUID:" << QString::fromNSString(camera.UUIDString);
            qDebug() << "Device serial:" << QString::fromNSString(camera.serialNumberString);
            qDebug() << "Device persistent ID:" << QString::fromNSString(camera.persistentIDString);
            qDebug() << "Transport type:" << camera.transportType;
            qDebug() << "USB Product ID:" << camera.usbProductID;
            qDebug() << "USB Vendor ID:" << camera.usbVendorID;
            qDebug() << "Camera capabilities:" << camera.capabilities;
            qDebug() << "Media files count:" << (camera.mediaFiles ? camera.mediaFiles.count : 0);
            qDebug() << "Device locked:" << camera.locked;
            qDebug() << "Device ejectable:" << camera.ejectable;
            
            if (self.controller) {
                [self emitFileListForCamera:camera];
            }
        }
    }
}

- (void)device:(ICDevice *)device didCloseSessionWithError:(NSError *)error {
    if (error) {
        qDebug() << "Session close error:" << QString::fromNSString(error.localizedDescription);
    } else {
        qDebug() << "Device session closed successfully";
    }
}

- (void)emitFileListForCamera:(ICCameraDevice *)camera {
    qDebug() << "=== FILE LIST DEBUG ===";
    qDebug() << "Camera media files count:" << (camera.mediaFiles ? camera.mediaFiles.count : 0);
    
    QList<DeviceFileInfo> fileList;
    
    for (ICCameraItem *item in camera.mediaFiles) {
        if ([item isKindOfClass:[ICCameraFile class]]) {
            ICCameraFile *file = (ICCameraFile *)item;
            
            qDebug() << "Processing file:" << QString::fromNSString(file.name);
            
            DeviceFileInfo info;
            info.filename = QString::fromNSString(file.name);
            info.size = file.fileSize;
            info.date = QDateTime::fromString(QString::fromNSString(file.creationDate.description), Qt::ISODate);
            info.type = QString::fromNSString(@"image"); // Default type since mediaType property doesn't exist
            info.thumbnail = QImage(); // No thumbnail for now
            
            fileList.append(info);
        }
    }
    
    qDebug() << "Emitting file list with" << fileList.size() << "files";
    if (self.controller) {
        emit self.controller->fileListReady(fileList);
    }
}

- (void)downloadFile:(NSString *)filename toPath:(NSString *)outputPath {
    qDebug() << "=== DOWNLOAD DEBUG ===";
    qDebug() << "Filename:" << QString::fromNSString(filename);
    qDebug() << "Output path:" << QString::fromNSString(outputPath);
    
    // Find the file in the camera's media files
    ICCameraFile *targetFile = nil;
    for (ICCameraItem *item in self.lastCameraDevice.mediaFiles) {
        if ([item isKindOfClass:[ICCameraFile class]]) {
            ICCameraFile *file = (ICCameraFile *)item;
            qDebug() << "Checking item:" << QString::fromNSString(file.name);
            if ([file.name isEqualToString:filename]) {
                targetFile = file;
                qDebug() << "Found target file:" << QString::fromNSString(file.name);
                qDebug() << "File size:" << file.fileSize;
                break;
            }
        }
    }
    
    if (!targetFile) {
        qDebug() << "File not found:" << QString::fromNSString(filename);
        if (self.controller) {
            emit self.controller->fileDownloadError(QString::fromNSString(filename), "File not found on device");
        }
        return;
    }
    
    // Add to download queue
    NSDictionary *downloadInfo = @{
        @"file": targetFile,
        @"outputPath": outputPath,
        @"filename": filename
    };
    [self.pendingDownloads addObject:downloadInfo];
    qDebug() << "Added to download queue. Queue size:" << self.pendingDownloads.count;
    
    // Process queue
    [self processDownloadQueue];
}

- (void)downloadAllFiles:(NSString *)outputDirectory {
    qDebug() << "=== BULK DOWNLOAD DEBUG ===";
    qDebug() << "Output directory:" << QString::fromNSString(outputDirectory);
    qDebug() << "Camera device found:" << QString::fromNSString(self.lastCameraDevice.name);
    qDebug() << "Media files count:" << (self.lastCameraDevice.mediaFiles ? self.lastCameraDevice.mediaFiles.count : 0);
    qDebug() << "Device capabilities:" << self.lastCameraDevice.capabilities;
    
    // Create output directory if it doesn't exist
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *createError = nil;
    if (![fileManager createDirectoryAtPath:outputDirectory withIntermediateDirectories:YES attributes:nil error:&createError]) {
        qDebug() << "Failed to create directory:" << QString::fromNSString(createError.localizedDescription);
        return;
    }
    
    // Download all files using the AppleOffloadTool approach
    for (ICCameraItem *item in self.lastCameraDevice.mediaFiles) {
        if ([item isKindOfClass:[ICCameraFile class]]) {
            ICCameraFile *file = (ICCameraFile *)item;
            
            qDebug() << "Processing file:" << QString::fromNSString(file.name);
            
            // Create a unique filename
            NSString *originalName = file.name;
            NSString *fileExtension = [originalName pathExtension];
            NSString *finalName = [NSString stringWithFormat:@"%@_%@.%@", 
                                   [originalName stringByDeletingPathExtension],
                                   [NSDate date].description,
                                   fileExtension];
            
            // Use the exact same approach as AppleOffloadTool
            NSDictionary *options = @{
                @"ICDownloadOptionDownloadsDirectoryURL": [NSURL fileURLWithPath:outputDirectory],
                @"ICDownloadOptionSaveAsFilename": finalName,
                @"ICDownloadOptionOverwrite": @YES
            };
            
            qDebug() << "Downloading with options:" << QString::fromNSString([options description]);
            
            [self.lastCameraDevice requestDownloadFile:file options:options downloadDelegate:self didDownloadSelector:@selector(didDownloadFile:error:options:contextInfo:) contextInfo:nil];
        }
    }
}

- (void)processDownloadQueue {
    if (self.pendingDownloads.count == 0) {
        qDebug() << "Download queue is empty";
        return;
    }
    
    NSDictionary *downloadInfo = self.pendingDownloads.firstObject;
    ICCameraFile *targetFile = downloadInfo[@"file"];
    NSString *outputPath = downloadInfo[@"outputPath"];
    NSString *filename = downloadInfo[@"filename"];
    
    [self tryDownloadFile:targetFile withOutputPath:outputPath andFilename:filename];
}

- (void)tryDownloadFile:(ICCameraFile *)targetFile withOutputPath:(NSString *)outputPath andFilename:(NSString *)filename {
    qDebug() << "Trying download method: requestDownloadFile with AppleOffloadTool approach";

    // Create the directory if it doesn't exist (exactly like AppleOffloadTool)
    NSString *directoryPath = [outputPath stringByDeletingLastPathComponent];
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *createError = nil;
    
    // Create directory with intermediate directories (like AppleOffloadTool)
    if (![fileManager createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:&createError]) {
        qDebug() << "Failed to create directory:" << QString::fromNSString(createError.localizedDescription);
        return;
    }

    // Use the EXACT same options as AppleOffloadTool (using string keys for Objective-C)
    NSDictionary *options = @{
        @"ICDownloadOptionDownloadsDirectoryURL": [NSURL fileURLWithPath:directoryPath],
        @"ICDownloadOptionSaveAsFilename": [outputPath lastPathComponent],
        @"ICDownloadOptionOverwrite": @YES
    };

    qDebug() << "Download options (AppleOffloadTool style):" << QString::fromNSString([options description]);
    qDebug() << "Target file:" << QString::fromNSString(targetFile.name);
    qDebug() << "Output path:" << QString::fromNSString(outputPath);
    qDebug() << "Directory path:" << QString::fromNSString(directoryPath);

    // Use the exact same method call as AppleOffloadTool
    [self.lastCameraDevice requestDownloadFile:targetFile 
                                       options:options 
                              downloadDelegate:self 
                           didDownloadSelector:@selector(didDownloadFile:error:options:contextInfo:) 
                                   contextInfo:nil];

    qDebug() << "Download request sent with AppleOffloadTool approach";
}

- (void)didDownloadFile:(ICCameraFile *)file error:(NSError *)error options:(NSDictionary *)options contextInfo:(void *)contextInfo {
    qDebug() << "=== DOWNLOAD CALLBACK (ENHANCED DIAGNOSTICS) ===";
    qDebug() << "File:" << QString::fromNSString(file.name);
    qDebug() << "File size:" << file.fileSize;
    qDebug() << "File UTI:" << QString::fromNSString(file.UTI);
    qDebug() << "Options:" << QString::fromNSString([options description]);

    // Remove the first item from the queue
    if (self.pendingDownloads.count > 0) {
        [self.pendingDownloads removeObjectAtIndex:0];
        qDebug() << "Removed from queue. Remaining:" << self.pendingDownloads.count;
    }

    if (error) {
        qDebug() << "=== DOWNLOAD ERROR ANALYSIS ===";
        qDebug() << "ERROR:" << QString::fromNSString(error.localizedDescription);
        qDebug() << "Error code:" << error.code;
        qDebug() << "Error domain:" << QString::fromNSString(error.domain);
        
        // Detailed error analysis for -9934
        if (error.code == -9934) {
            qDebug() << "*** ERROR -9934 ANALYSIS ***";
            qDebug() << "This error typically means:";
            qDebug() << "1. Device access restriction (device locked/untrusted)";
            qDebug() << "2. Insufficient permissions for file access";
            qDebug() << "3. iOS security policy preventing access";
            qDebug() << "4. File is protected/encrypted";
            qDebug() << "5. ImageCaptureCore incompatibility with this iOS version";
            
            qDebug() << "Current device state:";
            if (self.lastCameraDevice) {
                qDebug() << "- Device locked:" << self.lastCameraDevice.locked;
                qDebug() << "- Capabilities:" << self.lastCameraDevice.capabilities;
                qDebug() << "- Transport type:" << self.lastCameraDevice.transportType;
            }
        }

        if (self.controller) {
            emit self.controller->fileDownloadError(QString::fromNSString(file.name), QString::fromNSString(error.localizedDescription));
        }
    } else {
        qDebug() << "Download successful!";

        // Get the downloaded file path from options
        NSURL *downloadedURL = options[@"ICDownloadOptionDownloadsDirectoryURL"];
        if (downloadedURL) {
            NSString *filename = options[@"ICDownloadOptionSaveAsFilename"];
            if (!filename) {
                filename = file.name;
            }
            
            NSString *fullPath = [[downloadedURL path] stringByAppendingPathComponent:filename];

            // Check if file actually exists
            NSFileManager *fileManager = [NSFileManager defaultManager];
            BOOL fileExists = [fileManager fileExistsAtPath:fullPath];
            qDebug() << "File exists at path:" << fileExists;
            qDebug() << "Full path:" << QString::fromNSString(fullPath);

            if (fileExists) {
                NSDictionary *attributes = [fileManager attributesOfItemAtPath:fullPath error:nil];
                NSNumber *fileSize = [attributes objectForKey:NSFileSize];
                qDebug() << "Downloaded file size:" << [fileSize longLongValue] << "bytes";
            }

            if (self.controller) {
                emit self.controller->fileDownloaded(QString::fromNSString(file.name), QString::fromNSString(fullPath));
            }
        }
    }

    // Process next item in queue
    [self processDownloadQueue];
}

- (void)downloadWithPhotosFramework:(NSString *)outputDirectory {
    qDebug() << "=== PHOTOS FRAMEWORK DEBUG ===";
    qDebug() << "Output directory:" << QString::fromNSString(outputDirectory);
    
    // Request photo library access
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    qDebug() << "Photo library authorization status:" << status;
    
    if (status == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            qDebug() << "Authorization result:" << status;
            if (status == PHAuthorizationStatusAuthorized) {
                [self performPhotosDownload:outputDirectory];
            } else {
                qDebug() << "Photo library access denied";
            }
        }];
    } else if (status == PHAuthorizationStatusAuthorized) {
        [self performPhotosDownload:outputDirectory];
    } else {
        qDebug() << "Photo library access denied or restricted";
    }
}

- (void)performPhotosDownload:(NSString *)outputDirectory {
    qDebug() << "=== PERFORMING PHOTOS DOWNLOAD ===";
    
    // Create output directory
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSError *createError = nil;
    if (![fileManager createDirectoryAtPath:outputDirectory withIntermediateDirectories:YES attributes:nil error:&createError]) {
        qDebug() << "Failed to create directory:" << QString::fromNSString(createError.localizedDescription);
        return;
    }
    
    // Fetch all photos
    PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
    fetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    
    PHFetchResult *fetchResult = [PHAsset fetchAssetsWithOptions:fetchOptions];
    qDebug() << "Found" << fetchResult.count << "photos/videos";
    
    // Download each asset
    for (int i = 0; i < fetchResult.count; i++) {
        PHAsset *asset = [fetchResult objectAtIndex:i];
        qDebug() << "Processing asset" << i << "of" << fetchResult.count;
        
        // Get the filename
        NSString *filename = [NSString stringWithFormat:@"IMG_%04d", i + 1];
        if (asset.mediaType == PHAssetMediaTypeImage) {
            filename = [filename stringByAppendingString:@".jpg"];
        } else if (asset.mediaType == PHAssetMediaTypeVideo) {
            filename = [filename stringByAppendingString:@".mov"];
        }
        
        NSString *outputPath = [outputDirectory stringByAppendingPathComponent:filename];
        qDebug() << "Downloading to:" << QString::fromNSString(outputPath);
        
        // Download the asset
        [[PHImageManager defaultManager] requestImageDataAndOrientationForAsset:asset options:nil resultHandler:^(NSData * _Nullable imageData, NSString * _Nullable dataUTI, CGImagePropertyOrientation orientation, NSDictionary * _Nullable info) {
            if (imageData) {
                [imageData writeToFile:outputPath atomically:YES];
                qDebug() << "Successfully downloaded:" << QString::fromNSString(filename);
            } else {
                qDebug() << "Failed to download:" << QString::fromNSString(filename);
            }
        }];
    }
}

// Add the missing protocol methods that AppleOffloadTool has
- (void)deviceDidBecomeReady:(ICDevice *)device {
    qDebug() << "Device is ready:" << QString::fromNSString(device.name);
}

- (void)deviceDidBecomeReadyWithCompleteContentCatalog:(ICCameraDevice *)device {
    qDebug() << "Device is ready with complete content catalog:" << (device.mediaFiles ? device.mediaFiles.count : 0) << "items";
}

- (void)cameraDevice:(ICCameraDevice *)camera didAddItems:(NSArray<ICCameraItem *> *)items {
    qDebug() << "Camera added items:" << items.count;
}

- (void)cameraDevice:(ICCameraDevice *)camera didRemoveItems:(NSArray<ICCameraItem *> *)items {
    qDebug() << "Camera removed items:" << items.count;
}

- (void)cameraDevice:(ICCameraDevice *)camera didReceiveThumbnail:(CGImageRef)thumbnail forItem:(ICCameraItem *)item error:(NSError *)error {
    if (error) {
        qDebug() << "Error fetching thumbnail:" << QString::fromNSString(error.localizedDescription);
    }
}

- (void)cameraDevice:(ICCameraDevice *)camera didReceiveMetadata:(NSDictionary *)metadata forItem:(ICCameraItem *)item error:(NSError *)error {
    if (error) {
        qDebug() << "Error receiving metadata:" << QString::fromNSString(error.localizedDescription);
    }
}

- (void)cameraDevice:(ICCameraDevice *)camera didRenameItems:(NSArray<ICCameraItem *> *)items {
    qDebug() << "Camera renamed items:" << items.count;
}

- (void)cameraDeviceDidChangeCapability:(ICCameraDevice *)camera {
    qDebug() << "Camera device capability changed:" << QString::fromNSString(camera.name);
}

- (void)cameraDevice:(ICCameraDevice *)camera didReceivePTPEvent:(NSData *)eventData {
    qDebug() << "PTP event received with length:" << eventData.length << "bytes";
}

- (void)cameraDeviceDidRemoveAccessRestriction:(ICDevice *)device {
    qDebug() << "Access restriction removed for:" << QString::fromNSString(device.name);
}

- (void)cameraDeviceDidEnableAccessRestriction:(ICDevice *)device {
    qDebug() << "Access restriction enabled for:" << QString::fromNSString(device.name);
}

@end

// Private implementation class
class DeviceControllerPrivate {
public:
    DeviceDelegate *delegate;
    ICDeviceBrowser *deviceBrowser;
    
    DeviceControllerPrivate() : delegate(nil), deviceBrowser(nil) {}
    ~DeviceControllerPrivate() {
        if (deviceBrowser) {
            [deviceBrowser stop];
            [deviceBrowser release];
        }
        if (delegate) {
            [delegate release];
        }
    }
};

DeviceController::DeviceController(QObject *parent) : QObject(parent), d(new DeviceControllerPrivate()) {
    d->delegate = [[DeviceDelegate alloc] init];
    d->delegate.controller = this;
    
    d->deviceBrowser = [[ICDeviceBrowser alloc] init];
    d->deviceBrowser.delegate = d->delegate;
    d->deviceBrowser.browsedDeviceTypeMask = ICDeviceTypeMask(
        ICDeviceTypeMaskCamera | ICDeviceLocationTypeMaskLocal
    );
    
    [d->deviceBrowser start];
    qDebug() << "Device browser started";
}

DeviceController::~DeviceController() {
    delete d;
}

void DeviceController::startMonitoring() {
    // Already started in constructor
}

void DeviceController::refreshFiles() {
    if (d->delegate.lastCameraDevice) {
        [d->delegate emitFileListForCamera:d->delegate.lastCameraDevice];
    }
}

void DeviceController::downloadFile(const QString &filename, const QString &outputPath) {
    [d->delegate downloadFile:filename.toNSString() toPath:outputPath.toNSString()];
}

void DeviceController::downloadAllFiles(const QString &outputDirectory) {
    [d->delegate downloadAllFiles:outputDirectory.toNSString()];
}

void DeviceController::downloadWithPhotosFramework(const QString &outputDirectory) {
    [d->delegate downloadWithPhotosFramework:outputDirectory.toNSString()];
}



