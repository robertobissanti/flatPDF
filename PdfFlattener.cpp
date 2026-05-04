#include "PdfFlattener.h"

#include <QDebug>
#include <QCoreApplication>
#include <QTemporaryDir>
#include <QProcess>
#include <QProcessEnvironment>
#include <QDir>
#include <QImage>
#include <QPdfWriter>
#include <QPainter>
#include <QPageLayout>
#include <QPageSize>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>
#include <QDesktopServices>
#include <QStringList>
#include <QFile>
#include <QCollator>
#include <QSet>
#include <QtMath>
#include <algorithm>

PdfFlattener::PdfFlattener(QObject* parent)
    : QObject(parent) {}

void PdfFlattener::setDpi(int value) {
    if (value == m_dpi) return;
    if (value <= 0) return; // ignore invalid
    m_dpi = value;
    emit dpiChanged();
}

void PdfFlattener::setQuality(int value) {
    if (value == m_quality) return;
    if (value < 0 || value > 100) return; // ignore invalid
    m_quality = value;
    emit qualityChanged();
}

void PdfFlattener::setImageFormat(const QString& value) {
    QString normalized = value.trimmed().toLower();
    if (normalized == QStringLiteral("jpeg")) normalized = QStringLiteral("jpg");
    if (normalized != QStringLiteral("png") && normalized != QStringLiteral("jpg")) return;
    if (normalized == m_imageFormat) return;
    m_imageFormat = normalized;
    emit imageFormatChanged();
}

void PdfFlattener::setPdftoppmPath(const QString& p) {
    if (p == m_pdftoppmPath) return;
    m_pdftoppmPath = p;
    emit pdftoppmPathChanged();
}

QString PdfFlattener::resolvePdftoppm() const {
    auto isExec = [](const QString& p) {
        QFileInfo fi(p);
        return fi.exists() && fi.isFile() && fi.isExecutable();
    };

    if (!m_pdftoppmPath.isEmpty() && isExec(m_pdftoppmPath))
        return QFileInfo(m_pdftoppmPath).absoluteFilePath();

    // macOS app bundle Resources
    const QString bundled = QCoreApplication::applicationDirPath() + "/../Resources/pdftoppm";
    if (isExec(bundled)) return bundled;

    // PATH lookup
    const QString inPath = QStandardPaths::findExecutable("pdftoppm");
    if (!inPath.isEmpty()) return inPath;

    // Common locations (Homebrew, MacPorts, legacy)
    const QStringList common = {
        "/opt/homebrew/bin/pdftoppm",
        "/usr/local/bin/pdftoppm",
        "/opt/local/bin/pdftoppm",
        "/usr/bin/pdftoppm"
    };
    for (const QString& c : common) {
        if (isExec(c)) return c;
    }
    return QString();
}

static QString asLocalFilePath(const QString& maybeUrl)
{
    if (maybeUrl.startsWith("file:", Qt::CaseInsensitive)) {
        const QUrl u(maybeUrl);
        if (u.isLocalFile()) return u.toLocalFile();
        return u.toString();
    }
    return maybeUrl;
}

static QString resolvePdfinfo()
{
    auto isExec = [](const QString& p) {
        QFileInfo fi(p);
        return fi.exists() && fi.isFile() && fi.isExecutable();
    };

    const QString inPath = QStandardPaths::findExecutable("pdfinfo");
    if (!inPath.isEmpty()) return inPath;

    const QStringList common = {
        "/opt/homebrew/bin/pdfinfo",
        "/usr/local/bin/pdfinfo",
        "/opt/local/bin/pdfinfo",
        "/usr/bin/pdfinfo"
    };
    for (const QString& c : common) {
        if (isExec(c)) return c;
    }
    return QString();
}

static int pdfPageCount(const QString& pdfPath, QString* error)
{
    const QString tool = resolvePdfinfo();
    if (tool.isEmpty()) {
        if (error) *error = QStringLiteral("pdfinfo non trovato. Installa poppler per usare la stima rapida.");
        return 0;
    }

    QProcess p;
    p.start(tool, QStringList{pdfPath});
    if (!p.waitForStarted()) {
        if (error) *error = QStringLiteral("Impossibile avviare pdfinfo: %1").arg(p.errorString());
        return 0;
    }
    if (!p.waitForFinished(-1) || p.exitStatus() != QProcess::NormalExit || p.exitCode() != 0) {
        if (error) *error = QStringLiteral("pdfinfo non riuscito: %1").arg(QString::fromLocal8Bit(p.readAllStandardError()));
        return 0;
    }

    const QString output = QString::fromLocal8Bit(p.readAllStandardOutput());
    const QStringList lines = output.split('\n');
    for (const QString& line : lines) {
        if (line.startsWith(QStringLiteral("Pages:"), Qt::CaseInsensitive)) {
            bool ok = false;
            const int pages = line.section(':', 1).trimmed().toInt(&ok);
            if (ok && pages > 0) return pages;
        }
    }

    if (error) *error = QStringLiteral("Impossibile leggere il numero di pagine dal PDF.");
    return 0;
}

static QList<int> quickSamplePages(int pageCount)
{
    QList<int> pages;
    if (pageCount <= 0) return pages;

    const int sampleCount = qMax(1, qMin(10, qCeil(pageCount * 0.20)));
    if (sampleCount >= pageCount) {
        for (int page = 1; page <= pageCount; ++page) pages << page;
        return pages;
    }

    QSet<int> seen;
    for (int i = 0; i < sampleCount; ++i) {
        const double position = sampleCount == 1
            ? 1.0
            : 1.0 + (static_cast<double>(pageCount - 1) * i / (sampleCount - 1));
        int page = qRound(position);
        page = qBound(1, page, pageCount);
        if (!seen.contains(page)) {
            seen.insert(page);
            pages << page;
        }
    }

    for (int page = 1; pages.size() < sampleCount && page <= pageCount; ++page) {
        if (!seen.contains(page)) {
            seen.insert(page);
            pages << page;
        }
    }

    std::sort(pages.begin(), pages.end());
    return pages;
}

static QVariantMap makePreset(const QString& presetName)
{
    const QString key = presetName.trimmed().toLower();
    QVariantMap preset;

    if (key == QStringLiteral("lossless") || key == QStringLiteral("senza-perdite") || key == QStringLiteral("senza perdite")) {
        preset["name"] = QStringLiteral("Senza Perdite");
        preset["dpi"] = 300;
        preset["quality"] = 100;
        preset["imageFormat"] = QStringLiteral("png");
    } else if (key == QStringLiteral("max") || key == QStringLiteral("massima") || key == QStringLiteral("maximum")) {
        preset["name"] = QStringLiteral("Massima");
        preset["dpi"] = 300;
        preset["quality"] = 95;
        preset["imageFormat"] = QStringLiteral("jpg");
    } else if (key == QStringLiteral("low") || key == QStringLiteral("bassa")) {
        preset["name"] = QStringLiteral("Bassa");
        preset["dpi"] = 100;
        preset["quality"] = 60;
        preset["imageFormat"] = QStringLiteral("jpg");
    } else {
        preset["name"] = QStringLiteral("Standard");
        preset["dpi"] = 150;
        preset["quality"] = 85;
        preset["imageFormat"] = QStringLiteral("jpg");
    }

    return preset;
}

QVariantMap PdfFlattener::presetInfo(const QString& presetName) const
{
    return makePreset(presetName);
}

QVariantMap PdfFlattener::flatten(const QString& pdfPath, const QString& savePath) {
    return flattenInternal(pdfPath, savePath, true, false);
}

QVariantMap PdfFlattener::flattenWithOptions(const QString& pdfPath, const QString& savePath,
                                             int dpi, int quality, const QString& imageFormat,
                                             bool openOutputFolder) {
    QString normalizedFormat = imageFormat.trimmed().toLower();
    if (normalizedFormat == QStringLiteral("jpeg")) normalizedFormat = QStringLiteral("jpg");
    if (normalizedFormat != QStringLiteral("png") && normalizedFormat != QStringLiteral("jpg")) {
        return QVariantMap{{"success", false}, {"error", QStringLiteral("Formato immagine deve essere 'png' o 'jpg'.")}};
    }

    const int oldDpi = m_dpi;
    const int oldQuality = m_quality;
    const QString oldFormat = m_imageFormat;

    setDpi(dpi);
    setQuality(quality);
    setImageFormat(normalizedFormat);
    QVariantMap res = flattenInternal(pdfPath, savePath, openOutputFolder, false);

    setDpi(oldDpi);
    setQuality(oldQuality);
    setImageFormat(oldFormat);
    return res;
}

QVariantMap PdfFlattener::flattenWithPreset(const QString& pdfPath, const QString& savePath,
                                            const QString& presetName, bool openOutputFolder) {
    const QVariantMap preset = makePreset(presetName);
    return flattenWithOptions(pdfPath, savePath,
                              preset.value("dpi").toInt(),
                              preset.value("quality").toInt(),
                              preset.value("imageFormat").toString(),
                              openOutputFolder);
}

QVariantMap PdfFlattener::estimateWithOptions(const QString& pdfPath, int dpi, int quality,
                                              const QString& imageFormat) {
    QTemporaryDir outDir;
    if (!outDir.isValid()) {
        return QVariantMap{{"success", false}, {"error", QStringLiteral("Impossibile creare una cartella temporanea per la stima.")}};
    }

    const QString inPath = asLocalFilePath(pdfPath);
    QString pageCountError;
    const int pages = pdfPageCount(inPath, &pageCountError);
    if (pages <= 0) {
        return QVariantMap{{"success", false}, {"error", pageCountError}};
    }

    const QList<int> samplePages = quickSamplePages(pages);
    if (samplePages.isEmpty()) {
        return QVariantMap{{"success", false}, {"error", QStringLiteral("Impossibile selezionare pagine campione.")}};
    }

    const QString tmpPdf = outDir.path() + "/estimate-sample.pdf";
    QString normalizedFormat = imageFormat.trimmed().toLower();
    if (normalizedFormat == QStringLiteral("jpeg")) normalizedFormat = QStringLiteral("jpg");
    if (normalizedFormat != QStringLiteral("png") && normalizedFormat != QStringLiteral("jpg")) {
        return QVariantMap{{"success", false}, {"error", QStringLiteral("Formato immagine deve essere 'png' o 'jpg'.")}};
    }

    const int oldDpi = m_dpi;
    const int oldQuality = m_quality;
    const QString oldFormat = m_imageFormat;

    setDpi(dpi);
    setQuality(quality);
    setImageFormat(normalizedFormat);
    QVariantMap res = flattenInternal(pdfPath, tmpPdf, false, true, samplePages);
    setDpi(oldDpi);
    setQuality(oldQuality);
    setImageFormat(oldFormat);
    if (!res.value("success").toBool()) return res;

    const QFileInfo fi(tmpPdf);
    const qint64 sampleBytes = fi.size();
    const int sampleCount = samplePages.size();
    const qint64 estimatedBytes = qCeil(static_cast<double>(sampleBytes) * pages / sampleCount);

    res["bytes"] = sampleBytes;
    res["estimatedBytes"] = estimatedBytes;
    res["estimatedMiB"] = QString::number(static_cast<double>(estimatedBytes) / 1024.0 / 1024.0, 'f', 2);
    res["pageCount"] = pages;
    res["samplePages"] = sampleCount;
    res["estimateMode"] = QStringLiteral("quick");
    QFile::remove(tmpPdf);
    return res;
}

QVariantMap PdfFlattener::estimateWithPreset(const QString& pdfPath, const QString& presetName) {
    const QVariantMap preset = makePreset(presetName);
    return estimateWithOptions(pdfPath,
                               preset.value("dpi").toInt(),
                               preset.value("quality").toInt(),
                               preset.value("imageFormat").toString());
}

QVariantMap PdfFlattener::flattenInternal(const QString& pdfPath, const QString& savePath,
                                          bool openOutputFolder, bool estimating,
                                          const QList<int>& samplePages) {
    emit processingStarted();
    QVariantMap res;

    auto fail = [this, &res, estimating](const QString& msg) {
        res["success"] = false;
        res["error"] = msg;
        if (!estimating) emit finished(false, QString(), msg);
        emit processingFinished();
        return res;
    };

    const QString inPath = asLocalFilePath(pdfPath);
    const QString outPath = asLocalFilePath(savePath);

    qDebug() << "Percorso di input ricevuto:" << pdfPath;
    qDebug() << "Percorso di input convertito:" << inPath;
    qDebug() << "Percorso di output ricevuto:" << savePath;
    qDebug() << "Percorso di output convertito:" << outPath;

    if (inPath.isEmpty()) return fail("Percorso PDF non valido.");
    if (outPath.isEmpty()) return fail("Percorso di salvataggio non valido.");
    if (m_dpi <= 0) return fail("DPI deve essere maggiore di 0.");
    if (m_quality < 0 || m_quality > 100) return fail("Qualità deve essere tra 0 e 100.");
    if (m_imageFormat != QStringLiteral("png") && m_imageFormat != QStringLiteral("jpg")) {
        return fail("Formato immagine deve essere 'png' o 'jpg'.");
    }

    QTemporaryDir tmpDir;
    if (!tmpDir.isValid()) return fail("Impossibile creare una cartella temporanea.");

    QString tool = resolvePdftoppm();
    if (tool.isEmpty()) {
        return fail(QStringLiteral(
            "pdftoppm non trovato.\n" \
            "Imposta PdfFlattener.pdftoppmPath o installa 'poppler' (es. brew install poppler)."));
    }
    auto makeArgs = [&](const QString& prefix, int page) {
        QStringList args;
        if (m_imageFormat == QStringLiteral("png")) {
            args << "-png";
        } else {
            args << "-jpeg" << "-jpegopt" << QStringLiteral("quality=%1").arg(m_quality);
        }
        if (page > 0) {
            args << "-f" << QString::number(page) << "-l" << QString::number(page);
        }
        args << "-r" << QString::number(m_dpi)
             << inPath
             << prefix;
        return args;
    };

    emit progress(QStringLiteral("Eseguo pdftoppm…"));
    auto run_pdftoppm = [&](const QString& exe, const QStringList& args)->QPair<int, QString> {
        QProcess p;

        QObject::connect(&p, &QProcess::readyReadStandardOutput, [&](){
            const QByteArray output = p.readAllStandardOutput();
            qDebug() << "pdftoppm stdout:" << QString::fromLocal8Bit(output);
        });
        QObject::connect(&p, &QProcess::readyReadStandardError, [&](){
            const QByteArray error = p.readAllStandardError();
            qDebug() << "pdftoppm stderr:" << QString::fromLocal8Bit(error);
        });
        QObject::connect(&p, &QProcess::errorOccurred, [&](QProcess::ProcessError error){
            qDebug() << "pdftoppm process error:" << error;
        });

        // If using bundled tool, help the dynamic linker find libs in Contents/lib
        if (exe.contains("/Contents/Resources/pdftoppm")) {
            const QString libDir = QCoreApplication::applicationDirPath() + "/../lib";
            QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
            const QString dyld = env.value("DYLD_LIBRARY_PATH");
            const QString dyldfb = env.value("DYLD_FALLBACK_LIBRARY_PATH");
            env.insert("DYLD_LIBRARY_PATH", libDir + (dyld.isEmpty()?"":":"+dyld));
            env.insert("DYLD_FALLBACK_LIBRARY_PATH", libDir + (dyldfb.isEmpty()?"":":"+dyldfb));
            p.setProcessEnvironment(env);
        }
        p.start(exe, args);
        if (!p.waitForStarted()) {
            return qMakePair(-999, QStringLiteral("Impossibile avviare %1: %2").arg(exe, p.errorString()));
        }
        if (!p.waitForFinished(-1) || p.exitStatus() != QProcess::NormalExit) {
            const QByteArray err = p.readAllStandardError();
            qDebug() << "pdftoppm finished with error. Exit code:" << p.exitCode() << "Exit status:" << p.exitStatus() << "Error:" << QString::fromLocal8Bit(err);
            return qMakePair(-998, QString::fromLocal8Bit(err));
        }
        return qMakePair(p.exitCode(), QString::fromLocal8Bit(p.readAllStandardError()));
    };

    auto runWithFallback = [&](const QStringList& args)->QPair<int, QString> {
        auto [code, err] = run_pdftoppm(tool, args);
        if (code == 0) return qMakePair(code, err);

        // Fallback: if bundled tool failed (e.g. missing libpoppler), try system one
        const bool wasBundled = tool.contains("/Contents/Resources/pdftoppm");
        if (wasBundled) {
            emit progress(QStringLiteral("Bundled pdftoppm fallito, provo quello di sistema…"));
            QString sysTool = QStandardPaths::findExecutable("pdftoppm");
            const QString bundledPath = QDir(QCoreApplication::applicationDirPath()).filePath("../Resources/pdftoppm");
            if (sysTool == bundledPath) sysTool.clear();
            if (sysTool.isEmpty()) {
                const QStringList common = {
                    "/opt/homebrew/bin/pdftoppm",
                    "/usr/local/bin/pdftoppm",
                    "/opt/local/bin/pdftoppm",
                    "/usr/bin/pdftoppm"
                };
                for (const QString& c : common) {
                    if (QFileInfo::exists(c) && QFileInfo(c).isExecutable()) {
                        sysTool = c;
                        if (sysTool != bundledPath) break;
                    }
                }
            }
            if (!sysTool.isEmpty() && sysTool != bundledPath) {
                auto [code2, err2] = run_pdftoppm(sysTool, args);
                if (code2 == 0) {
                    tool = sysTool; // success with system tool
                    return qMakePair(code2, err2);
                } else {
                    return qMakePair(code2, QStringLiteral("pdftoppm non riuscito (%1): %2").arg(sysTool, err2));
                }
            } else {
                return qMakePair(code, QStringLiteral("pdftoppm non riuscito (%1): %2").arg(tool, err.isEmpty()?QStringLiteral("Impossibile trovare un pdftoppm alternativo"):err));
            }
        } else {
            return qMakePair(code, QStringLiteral("pdftoppm non riuscito (%1): %2").arg(tool, err));
        }
    };

    if (samplePages.isEmpty()) {
        auto [code, err] = runWithFallback(makeArgs(tmpDir.path() + "/page", 0));
        if (code != 0) return fail(err);
    } else {
        for (int page : samplePages) {
            auto [code, err] = runWithFallback(makeArgs(tmpDir.path() + QStringLiteral("/sample-%1").arg(page), page));
            if (code != 0) return fail(err);
        }
    }

    emit progress(estimating ? QStringLiteral("Stimo dimensione PDF…") : QStringLiteral("Creo PDF…"));

    QPdfWriter writer(outPath);
    writer.setResolution(m_dpi);

    QPainter painter;
    bool firstPage = true;

    QDir dir(tmpDir.path());
    QStringList filters;
    if (m_imageFormat == QStringLiteral("png")) {
        filters << "*.png";
    } else {
        filters << "*.jpg" << "*.jpeg";
    }
    QStringList files = dir.entryList(filters, QDir::Files, QDir::Name);
    if (files.isEmpty()) {
        return fail(QStringLiteral("Nessuna pagina %1 trovata: controlla l'output di pdftoppm.").arg(m_imageFormat.toUpper()));
    }
    QCollator collator;
    collator.setNumericMode(true);
    std::sort(files.begin(), files.end(), [&collator](const QString& a, const QString& b) {
        return collator.compare(a, b) < 0;
    });

    for (int i = 0; i < files.size(); ++i) {
        QImage img(dir.filePath(files[i]));
        if (img.isNull()) continue;

        const double mmW = img.width()  * 25.4 / m_dpi;
        const double mmH = img.height() * 25.4 / m_dpi;

        QPageLayout pl;
        pl.setPageSize(QPageSize(QSizeF(mmW, mmH), QPageSize::Millimeter));
        pl.setOrientation(QPageLayout::Portrait);
        pl.setMargins(QMarginsF(0,0,0,0));
        writer.setPageLayout(pl);

        if (firstPage) {
            painter.begin(&writer);
            firstPage = false;
        } else {
            writer.newPage();
        }

        painter.drawImage(QPointF(0,0), img);
    }

    painter.end();

    // Validate the output file
    QFileInfo fi(outPath);
    if (!fi.exists()) {
        return fail(QStringLiteral("File di output non trovato: ") + savePath);
    }
    if (fi.size() == 0) {
        return fail(QStringLiteral("File di output vuoto: ") + savePath);
    }

    res["success"] = true;
    res["output"] = outPath;
    res["bytes"] = fi.size();
    res["dpi"] = m_dpi;
    res["quality"] = m_quality;
    res["imageFormat"] = m_imageFormat;
    if (!samplePages.isEmpty()) {
        res["samplePages"] = samplePages.size();
    }
    if (!estimating) emit finished(true, outPath, QString());
    emit processingFinished();
    if (openOutputFolder) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(fi.absolutePath()));
    }
    return res;
}
