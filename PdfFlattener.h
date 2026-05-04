#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QList>

class PdfFlattener : public QObject {
    Q_OBJECT
    Q_PROPERTY(int dpi READ dpi WRITE setDpi NOTIFY dpiChanged)
    Q_PROPERTY(int quality READ quality WRITE setQuality NOTIFY qualityChanged)
    Q_PROPERTY(QString imageFormat READ imageFormat WRITE setImageFormat NOTIFY imageFormatChanged)
    Q_PROPERTY(QString pdftoppmPath READ pdftoppmPath WRITE setPdftoppmPath NOTIFY pdftoppmPathChanged)

public:
    explicit PdfFlattener(QObject* parent = nullptr);

    Q_INVOKABLE QVariantMap flatten(const QString& pdfPath, const QString& savePath);
    Q_INVOKABLE QVariantMap flattenWithOptions(const QString& pdfPath, const QString& savePath,
                                               int dpi, int quality, const QString& imageFormat,
                                               bool openOutputFolder = true);
    Q_INVOKABLE QVariantMap flattenWithPreset(const QString& pdfPath, const QString& savePath,
                                              const QString& presetName,
                                              bool openOutputFolder = true);
    Q_INVOKABLE QVariantMap estimateWithOptions(const QString& pdfPath, int dpi, int quality,
                                                const QString& imageFormat);
    Q_INVOKABLE QVariantMap estimateWithPreset(const QString& pdfPath, const QString& presetName);
    Q_INVOKABLE QVariantMap presetInfo(const QString& presetName) const;

    int dpi() const { return m_dpi; }
    void setDpi(int newDpi);

    int quality() const { return m_quality; }
    void setQuality(int newQuality);

    QString imageFormat() const { return m_imageFormat; }
    void setImageFormat(const QString& newImageFormat);

    QString pdftoppmPath() const { return m_pdftoppmPath; }
    void setPdftoppmPath(const QString& newPdftoppmPath);

signals:
    void dpiChanged();
    void qualityChanged();
    void imageFormatChanged();
    void pdftoppmPathChanged();
    void processingStarted();
    void processingFinished();
    void progress(const QString& message);
    void finished(bool success, const QString& outputPath, const QString& error);

private:
    QString resolvePdftoppm() const;
    QVariantMap flattenInternal(const QString& pdfPath, const QString& savePath,
                                bool openOutputFolder, bool estimating,
                                const QList<int>& samplePages = QList<int>());

    int m_dpi = 150;
    int m_quality = 85;
    QString m_imageFormat = QStringLiteral("jpg");
    QString m_pdftoppmPath;
};
