#include "mainwindow.h"
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QGroupBox>
#include <QHeaderView>
#include <QMessageBox>
#include <QFileDialog>
#include <QSettings>
#include <QDir>
#include <QFile>
#include <QTextStream>
#include <QDateTime>
#include <QDebug>
#include <QCoreApplication>
#include <algorithm>

MainWindow::MainWindow(QWidget *parent) : QMainWindow(parent) {
    setupUi();
    setupTemplatePrompts();
    setupConversionUI();
    
    // Initialize device controller
    deviceController = new SwiftWrapper(this);
    connect(deviceController, &SwiftWrapper::deviceConnected, this, &MainWindow::onDeviceConnected);
    connect(deviceController, &SwiftWrapper::deviceDisconnected, this, &MainWindow::onDeviceDisconnected);
    connect(deviceController, &SwiftWrapper::fileListReady, this, &MainWindow::onFileListReceived);
    
    // Start device discovery
    deviceController->startDeviceDiscovery();
    
    // Load persistent output directory
    QSettings settings;
    QString defaultOutput = QDir::homePath() + "/Downloads/FeederOutput";
    outputDirectory = settings.value("outputDirectory", defaultOutput).toString();
    if (outputDirectory.isEmpty()) {
        outputDirectory = defaultOutput;
    }
    outputDirectoryEdit->setText(outputDirectory);
    logMessage(QString("Output directory: %1").arg(outputDirectory));
}

MainWindow::~MainWindow() {
    // Clean up temporary directory
    if (!tempDirectory.isEmpty()) {
        QDir tempDir(tempDirectory);
        if (tempDir.exists()) {
            tempDir.removeRecursively();
        }
    }
}

void MainWindow::setupUi() {
    QWidget *central = new QWidget(this);
    QVBoxLayout *mainLayout = new QVBoxLayout(central);
    
    // Status and log area
    statusLabel = new QLabel("Status: Initializing...", this);
    mainLayout->addWidget(statusLabel);
    
    logArea = new QTextEdit(this);
    logArea->setReadOnly(true);
    logArea->setMaximumHeight(150);
    logArea->setStyleSheet("QTextEdit { background-color: #2b2b2b; color: #ffffff; }");
    mainLayout->addWidget(logArea);
    
    // File table
    QGroupBox *tableGroupBox = new QGroupBox("Files", this);
    QVBoxLayout *tableLayout = new QVBoxLayout(tableGroupBox);
    
    // Table controls
    QHBoxLayout *tableControlsLayout = new QHBoxLayout();
    
    refreshButton = new QPushButton("Refresh", this);
    connect(refreshButton, &QPushButton::clicked, this, &MainWindow::onRefreshClicked);
    tableControlsLayout->addWidget(refreshButton);
    
    // Column visibility controls
    columnGroupBox = new QGroupBox("Columns", this);
    QHBoxLayout *columnLayout = new QHBoxLayout(columnGroupBox);
    
    filenameCheck = new QCheckBox("Filename", this);
    filenameCheck->setChecked(true);
    connect(filenameCheck, &QCheckBox::toggled, this, &MainWindow::onColumnCheckChanged);
    columnLayout->addWidget(filenameCheck);
    
    sizeCheck = new QCheckBox("Size", this);
    sizeCheck->setChecked(true);
    connect(sizeCheck, &QCheckBox::toggled, this, &MainWindow::onColumnCheckChanged);
    columnLayout->addWidget(sizeCheck);
    
    dateCheck = new QCheckBox("Date", this);
    dateCheck->setChecked(true);
    connect(dateCheck, &QCheckBox::toggled, this, &MainWindow::onColumnCheckChanged);
    columnLayout->addWidget(dateCheck);
    
    typeCheck = new QCheckBox("Type", this);
    typeCheck->setChecked(true);
    connect(typeCheck, &QCheckBox::toggled, this, &MainWindow::onColumnCheckChanged);
    columnLayout->addWidget(typeCheck);
    
    tableControlsLayout->addWidget(columnGroupBox);
    tableLayout->addLayout(tableControlsLayout);
    
    // File table
    fileTableWidget = new QTableWidget(this);
    fileTableWidget->setColumnCount(4);
    fileTableWidget->setHorizontalHeaderLabels({"Filename", "Size", "Date", "Type"});
    fileTableWidget->setSelectionBehavior(QAbstractItemView::SelectRows);
    fileTableWidget->setSelectionMode(QAbstractItemView::MultiSelection);
    fileTableWidget->horizontalHeader()->setStretchLastSection(true);
    tableLayout->addWidget(fileTableWidget);
    
    mainLayout->addWidget(tableGroupBox);
    
    // Progress bars
    QHBoxLayout *progressLayout = new QHBoxLayout();
    transferProgress = new QProgressBar(this);
    transferProgress->setVisible(false);
    conversionProgress = new QProgressBar(this);
    conversionProgress->setVisible(false);
    conversionProgress->setValue(0);
    progressLayout->addWidget(transferProgress);
    progressLayout->addWidget(conversionProgress);
    mainLayout->addLayout(progressLayout);

    QHBoxLayout *promptLayout = new QHBoxLayout();
    templatePromptBox = new QComboBox(this);
    promptLayout->addWidget(templatePromptBox);
    mainLayout->addLayout(promptLayout);

    setCentralWidget(central);
    setWindowTitle("Feeder - iPhone Media Manager");
    resize(900, 600);
}

void MainWindow::setupConversionUI() {
    // Conversion controls
    QHBoxLayout *conversionLayout = new QHBoxLayout();
    
    // Output directory selection
    conversionLayout->addWidget(new QLabel("Output:", this));
    outputDirectoryEdit = new QLineEdit(this);
    outputDirectoryEdit->setPlaceholderText("Click Browse or type path...");
    outputDirectoryEdit->setReadOnly(false); // Allow manual typing as fallback
    conversionLayout->addWidget(outputDirectoryEdit);
    
    // Connect text changed to update output directory
    connect(outputDirectoryEdit, &QLineEdit::textChanged, [this](const QString &text) {
        if (!text.isEmpty() && QDir(text).exists()) {
            outputDirectory = text;
            logMessage(QString("Output directory set to: %1").arg(text));
            
            // Enable conversion buttons if files are available
            int fileCount = fileTableWidget->rowCount();
            convertSelectedButton->setEnabled(fileCount > 0);
            convertAllButton->setEnabled(fileCount > 0);
        }
    });
    
    browseOutputButton = new QPushButton("Browse", this);
    connect(browseOutputButton, &QPushButton::clicked, this, &MainWindow::onBrowseOutputClicked);
    conversionLayout->addWidget(browseOutputButton);
    
    // File type filter
    conversionLayout->addWidget(new QLabel("Filter:", this));
    fileTypeFilterComboBox = new QComboBox(this);
    fileTypeFilterComboBox->addItem("All Files");
    fileTypeFilterComboBox->addItem("Videos Only");
    fileTypeFilterComboBox->addItem("Images Only");
    connect(fileTypeFilterComboBox, QOverload<const QString &>::of(&QComboBox::currentTextChanged), 
            this, &MainWindow::onFileTypeFilterChanged);
    conversionLayout->addWidget(fileTypeFilterComboBox);
    
    convertSelectedButton = new QPushButton("Convert Selected", this);
    convertSelectedButton->setEnabled(false);
    connect(convertSelectedButton, &QPushButton::clicked, this, &MainWindow::onConvertSelectedClicked);
    conversionLayout->addWidget(convertSelectedButton);
    
    convertAllButton = new QPushButton("Convert All", this);
    convertAllButton->setEnabled(false);
    connect(convertAllButton, &QPushButton::clicked, this, &MainWindow::onConvertAllClicked);
    conversionLayout->addWidget(convertAllButton);
    
    // Add conversion layout to main layout
    QWidget *central = qobject_cast<QWidget*>(centralWidget());
    if (central) {
        QVBoxLayout *mainLayout = qobject_cast<QVBoxLayout*>(central->layout());
        if (mainLayout) {
            mainLayout->insertLayout(mainLayout->count() - 1, conversionLayout);
        }
    }
}

void MainWindow::setupTemplatePrompts() {
    templatePromptBox->addItem("Sort by year");
    templatePromptBox->addItem("Sort by AI label");
    templatePromptBox->addItem("Sort by date");
    templatePromptBox->addItem("Sort by type");
}

void MainWindow::logMessage(const QString &msg) {
    QString timestamp = QDateTime::currentDateTime().toString("yyyy-MM-dd hh:mm:ss");
    QString logEntry = QString("[%1] %2").arg(timestamp).arg(msg);
    
    logArea->append(logEntry);
}

void MainWindow::saveLogToFile(const QString &msg) {
    // Save log to file in app directory
    QDir dir(QCoreApplication::applicationDirPath());
    QString logPath = dir.absoluteFilePath("feeder.log");
    
    QFile logFile(logPath);
    if (logFile.open(QIODevice::WriteOnly | QIODevice::Append)) {
        QTextStream stream(&logFile);
        stream << msg << "\n";
        logFile.close();
    }
}

void MainWindow::onDeviceConnected(const QString &deviceName) {
    logMessage(QString("Device connected: %1").arg(deviceName));
    statusLabel->setText(QString("Status: Connected to %1").arg(deviceName));
}

void MainWindow::onDeviceDisconnected(const QString &deviceName) {
    logMessage(QString("Device disconnected: %1").arg(deviceName));
    statusLabel->setText("Status: No device connected");
}

void MainWindow::onFileListReceived(const QStringList &fileList, const QStringList &sizeList, const QStringList &dateList) {
    // Sort files by filename
    QStringList sortedList = fileList;
    QStringList sortedSizeList = sizeList;
    QStringList sortedDateList = dateList;
    
    // Create triples for sorting
    QList<QPair<QString, QPair<QString, QString>>> fileTriples;
    for (int i = 0; i < fileList.size(); ++i) {
        QString date = (i < dateList.size()) ? dateList[i] : "Unknown";
        fileTriples.append(qMakePair(fileList[i], qMakePair(sizeList[i], date)));
    }
    
    // Sort by filename
    std::sort(fileTriples.begin(), fileTriples.end(), [](const QPair<QString, QPair<QString, QString>> &a, const QPair<QString, QPair<QString, QString>> &b) {
        return a.first.toLower() < b.first.toLower();
    });
    
    // Extract sorted lists
    sortedList.clear();
    sortedSizeList.clear();
    sortedDateList.clear();
    for (const auto &triple : fileTriples) {
        sortedList.append(triple.first);
        sortedSizeList.append(triple.second.first);
        sortedDateList.append(triple.second.second);
    }

    fileTableWidget->setRowCount(0);
    for (int i = 0; i < sortedList.size(); ++i) {
        const QString &filename = sortedList[i];
        const QString &filesize = sortedSizeList[i];
        const QString &filedate = sortedDateList[i];
        
        int row = fileTableWidget->rowCount();
        fileTableWidget->insertRow(row);
        fileTableWidget->setItem(row, 0, new QTableWidgetItem(filename));
        
        // Format file size
        QString sizeStr = filesize;
        if (sizeStr != "Unknown") {
            bool ok;
            qint64 bytes = sizeStr.toLongLong(&ok);
            if (ok) {
                sizeStr = humanFileSize(bytes);
            }
        }
        fileTableWidget->setItem(row, 1, new QTableWidgetItem(sizeStr));
        fileTableWidget->setItem(row, 2, new QTableWidgetItem(filedate)); // Use date from Swift
        
        // Guess type from extension
        QString ext = filename.section('.', -1).toLower();
        QString typeStr;
        if (ext == "mov" || ext == "mp4" || ext == "m4v" || ext == "3gp")
            typeStr = "Video";
        else if (ext == "jpg" || ext == "jpeg" || ext == "png" || ext == "heic" || ext == "heif")
            typeStr = "Image";
        else
            typeStr = "Other";
        
        fileTableWidget->setItem(row, 3, new QTableWidgetItem(typeStr));
    }
    updateTableColumns();
    filterFilesByType();
    
    // Enable buttons if we have files and output directory
    bool hasFiles = fileTableWidget->rowCount() > 0;
    bool hasOutputDir = !outputDirectory.isEmpty();
    convertSelectedButton->setEnabled(hasFiles && hasOutputDir);
    convertAllButton->setEnabled(hasFiles && hasOutputDir);
    
    qDebug() << "Files loaded:" << fileTableWidget->rowCount() << "Output dir:" << outputDirectory;
}

void MainWindow::onRefreshClicked() {
    if (deviceController) {
        // Get files from Swift controller
        QStringList files = deviceController->getDeviceFiles();
        QStringList sizes = deviceController->getDeviceFileSizes();
        QStringList dates = deviceController->getDeviceFileDates();
        onFileListReceived(files, sizes, dates);
    }
}

QString MainWindow::humanFileSize(qint64 bytes) const {
    static const char *sizes[] = {"B", "KB", "MB", "GB", "TB"};
    double len = bytes;
    int order = 0;
    while (len >= 1024.0 && order < 4) {
        order++;
        len = len/1024.0;
    }
    return QString::asprintf("%.2f %s", len, sizes[order]);
}

void MainWindow::onColumnCheckChanged() {
    updateTableColumns();
}

void MainWindow::updateTableColumns() {
    fileTableWidget->setColumnHidden(0, !filenameCheck->isChecked());
    fileTableWidget->setColumnHidden(1, !sizeCheck->isChecked());
    fileTableWidget->setColumnHidden(2, !dateCheck->isChecked());
    fileTableWidget->setColumnHidden(3, !typeCheck->isChecked());
}

void MainWindow::onConvertSelectedClicked() {
    if (outputDirectory.isEmpty()) {
        QMessageBox::warning(this, "No Output Directory", "Please select an output directory first.");
        return;
    }
    
    // Get selected rows
    QSet<int> selectedRows;
    for (QTableWidgetItem *item : fileTableWidget->selectedItems()) {
        selectedRows.insert(item->row());
    }
    
    if (selectedRows.isEmpty()) {
        QMessageBox::warning(this, "No Files Selected", "Please select files to convert.");
        return;
    }
    
    // Get selected filenames
    QStringList selectedFiles;
    for (int row : selectedRows) {
        QTableWidgetItem *filenameItem = fileTableWidget->item(row, 0);
        if (filenameItem) {
            selectedFiles.append(filenameItem->text());
        }
    }
    
    qDebug() << "=== SWIFT DOWNLOAD START ===";
    qDebug() << "Output directory:" << outputDirectory;
    qDebug() << "Selected files:" << selectedFiles;
    
    logMessage(QString("Starting Swift-based download of %1 selected files to %2...").arg(selectedFiles.size()).arg(outputDirectory));
    
    // Use Swift-based download
    if (deviceController->downloadSelectedFiles(selectedFiles, outputDirectory, "Feeder")) {
        logMessage("✓ Swift download initiated successfully");
        statusLabel->setText("Status: Downloading selected files...");
    } else {
        logMessage("✗ Swift download failed to start");
        statusLabel->setText("Status: Download failed");
    }
}

void MainWindow::onConvertAllClicked() {
    if (outputDirectory.isEmpty()) {
        QMessageBox::warning(this, "No Output Directory", "Please select an output directory first.");
        return;
    }
    
    // Get all visible filenames
    QStringList allFiles;
    for (int row = 0; row < fileTableWidget->rowCount(); ++row) {
        if (!fileTableWidget->isRowHidden(row)) {
            QTableWidgetItem *filenameItem = fileTableWidget->item(row, 0);
            if (filenameItem) {
                allFiles.append(filenameItem->text());
            }
        }
    }
    
    if (allFiles.isEmpty()) {
        QMessageBox::warning(this, "No Files", "No files available to convert.");
        return;
    }
    
    qDebug() << "=== SWIFT DOWNLOAD ALL START ===";
    qDebug() << "Output directory:" << outputDirectory;
    qDebug() << "All files:" << allFiles;
    
    logMessage(QString("Starting Swift-based download of all %1 files to %2...").arg(allFiles.size()).arg(outputDirectory));
    
    // Use Swift-based download for all files
    if (deviceController->downloadAllFiles(outputDirectory, "Feeder")) {
        logMessage("✓ Swift download all files initiated successfully");
        statusLabel->setText("Status: Downloading all files...");
    } else {
        logMessage("✗ Swift download all files failed to start");
        statusLabel->setText("Status: Download failed");
    }
}

void MainWindow::onBrowseOutputClicked() {
    logMessage("Opening directory selector...");
    
    // Use a simpler approach to avoid the ViewBridge crash
    QString defaultDir = QDir::homePath() + "/Downloads";
    
    // Try to create a simple file dialog without delegate issues
    QFileDialog dialog(this);
    dialog.setFileMode(QFileDialog::Directory);
    dialog.setOption(QFileDialog::ShowDirsOnly, true);
    dialog.setOption(QFileDialog::DontUseNativeDialog, true); // Use Qt dialog instead of native
    dialog.setDirectory(defaultDir);
    dialog.setWindowTitle("Select Output Directory");
    
    if (dialog.exec() == QDialog::Accepted) {
        QStringList selected = dialog.selectedFiles();
        if (!selected.isEmpty()) {
            QString dir = selected.first();
            outputDirectory = dir;
            outputDirectoryEdit->setText(dir);
            
            // Save the selection persistently
            QSettings settings;
            settings.setValue("outputDirectory", dir);
            
            logMessage(QString("Output directory set to: %1 (saved)").arg(dir));
            
            // Enable conversion buttons if files are available
            int fileCount = fileTableWidget->rowCount();
            convertSelectedButton->setEnabled(fileCount > 0);
            convertAllButton->setEnabled(fileCount > 0);
        }
    } else {
        logMessage("Directory selection cancelled");
    }
}

void MainWindow::onFileTypeFilterChanged() {
    filterFilesByType();
}

void MainWindow::filterFilesByType() {
    QString filterText = fileTypeFilterComboBox->currentText();
    
    for (int row = 0; row < fileTableWidget->rowCount(); ++row) {
        QTableWidgetItem *typeItem = fileTableWidget->item(row, 3); // Type column
        if (!typeItem) continue;
        
        QString fileType = typeItem->text().toLower();
        bool showRow = true;
        
        if (filterText == "Videos Only") {
            showRow = fileType == "video";
        } else if (filterText == "Images Only") {
            showRow = fileType == "image";
        }
        // "All Files" shows everything
        
        fileTableWidget->setRowHidden(row, !showRow);
    }
    
    // Update button states based on visible files
    int visibleFiles = 0;
    for (int row = 0; row < fileTableWidget->rowCount(); ++row) {
        if (!fileTableWidget->isRowHidden(row)) {
            visibleFiles++;
        }
    }
    
    convertAllButton->setEnabled(visibleFiles > 0);
    convertSelectedButton->setEnabled(visibleFiles > 0);
} 