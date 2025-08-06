#pragma once
#include "swift_wrapper.h"
#include <QMainWindow>
#include <QTextEdit>
#include <QLabel>
#include <QProgressBar>
#include <QComboBox>
#include <QPushButton>
#include <QTableWidget>
#include <QGroupBox>
#include <QCheckBox>
#include <QLineEdit>
#include <QProcess>
#include <QQueue>
#include <QSettings>

class DeviceController;

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    MainWindow(QWidget *parent = nullptr);
    ~MainWindow();

    void logMessage(const QString &msg);

private:
    QLabel *statusLabel;
    QTextEdit *logArea;
    QProgressBar *transferProgress;
    QProgressBar *conversionProgress;
    QComboBox *templatePromptBox;
    QPushButton *refreshButton;
    QPushButton *convertSelectedButton;
    QPushButton *convertAllButton;
    QPushButton *browseOutputButton;
    QComboBox *fileTypeFilterComboBox;
    QLineEdit *outputDirectoryEdit;
    QTableWidget *fileTableWidget;
    QGroupBox *columnGroupBox;
    QCheckBox *filenameCheck;
    QCheckBox *sizeCheck;
    QCheckBox *dateCheck;
    QCheckBox *typeCheck;
                SwiftWrapper *deviceController;
    QString outputDirectory;
    QString tempDirectory;
    void setupUi();
    void setupTemplatePrompts();
    void saveLogToFile(const QString &msg);
    QString humanFileSize(qint64 bytes) const;
    void updateTableColumns();
    void setupConversionUI();
    void filterFilesByType();

private slots:
    void onDeviceConnected(const QString &deviceName);
    void onDeviceDisconnected(const QString &deviceName);
                void onFileListReceived(const QStringList &fileList, const QStringList &sizeList, const QStringList &dateList);
    void onRefreshClicked();
    void onColumnCheckChanged();
    void onConvertSelectedClicked();
    void onConvertAllClicked();
    void onBrowseOutputClicked();
    void onFileTypeFilterChanged();
}; 