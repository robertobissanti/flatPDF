#include <QCoreApplication>
#include <QApplication>
#include <QQmlApplicationEngine>
#include <QByteArray>
#include <QQmlEngine>
#include <QQmlContext>
#include <QDir>
#include <QStandardPaths>
#include <QCommandLineParser>
#include <QJsonDocument>
#include <QJsonObject>
#include <QTextStream>
#include <QAction>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include "PdfFlattener.h"
#ifdef Q_OS_MACOS
#include "MacAbout.h"
#endif

int main(int argc, char *argv[])
{
    // Force a non-native style to avoid AppKit NSAlert crashes
    qputenv("QT_QUICK_CONTROLS_STYLE", QByteArray("Fusion"));

    bool cliRequested = false;
    for (int i = 1; i < argc; ++i) {
        const QString arg = QString::fromLocal8Bit(argv[i]);
        if (arg == "--cli" || arg == "-c" || arg == "--guided" || arg == "-g"
            || arg == "--input" || arg == "-i" || arg.startsWith("--input=")
            || arg == "--output" || arg == "-o" || arg.startsWith("--output=")
            || arg == "--preset" || arg == "-p" || arg.startsWith("--preset=")
            || arg == "--dpi" || arg.startsWith("--dpi=")
            || arg == "--quality" || arg == "-q" || arg.startsWith("--quality=")
            || arg == "--format" || arg == "-f" || arg.startsWith("--format=")
            || arg == "--estimate" || arg == "-e" || arg == "--list-presets"
            || arg == "--pdftoppm" || arg.startsWith("--pdftoppm=")) {
            cliRequested = true;
            break;
        }
    }

    if (cliRequested) {
        QCoreApplication app(argc, argv);

        QCommandLineParser parser;
        parser.setApplicationDescription("Flatten PDF rasterizzando le pagine e ricreando un PDF piatto.");
        parser.addHelpOption();
        parser.addVersionOption();

        QCommandLineOption cliOpt(QStringList{"c", "cli"}, "Avvia in modalita CLI.");
        QCommandLineOption guidedOpt(QStringList{"g", "guided"}, "Modalita guidata CLI.");
        QCommandLineOption inputOpt(QStringList{"i", "input"}, "PDF di input.", "pdf");
        QCommandLineOption outputOpt(QStringList{"o", "output"}, "PDF di output.", "pdf");
        QCommandLineOption presetOpt(QStringList{"p", "preset"}, "Preset: lossless, massima, standard, bassa.", "name", "standard");
        QCommandLineOption dpiOpt("dpi", "DPI personalizzati.", "dpi");
        QCommandLineOption qualityOpt(QStringList{"q", "quality"}, "Qualita JPEG 0-100.", "quality");
        QCommandLineOption formatOpt(QStringList{"f", "format"}, "Formato intermedio: png o jpg.", "format");
        QCommandLineOption estimateOpt(QStringList{"e", "estimate"}, "Stima la dimensione finale senza salvare il PDF richiesto.");
        QCommandLineOption listPresetsOpt("list-presets", "Mostra i preset disponibili.");
        QCommandLineOption pdftoppmOpt("pdftoppm", "Percorso esplicito a pdftoppm.", "path");

        parser.addOption(cliOpt);
        parser.addOption(guidedOpt);
        parser.addOption(inputOpt);
        parser.addOption(outputOpt);
        parser.addOption(presetOpt);
        parser.addOption(dpiOpt);
        parser.addOption(qualityOpt);
        parser.addOption(formatOpt);
        parser.addOption(estimateOpt);
        parser.addOption(listPresetsOpt);
        parser.addOption(pdftoppmOpt);
        parser.process(app);

        QTextStream out(stdout);
        QTextStream in(stdin);

        PdfFlattener flattener;
        if (parser.isSet(pdftoppmOpt)) {
            flattener.setPdftoppmPath(parser.value(pdftoppmOpt));
        }

        const QStringList presetNames = {"lossless", "massima", "standard", "bassa"};
        if (parser.isSet(listPresetsOpt)) {
            for (const QString& name : presetNames) {
                const QVariantMap info = flattener.presetInfo(name);
                out << info.value("name").toString() << ": "
                    << info.value("dpi").toInt() << " DPI, "
                    << info.value("quality").toInt() << "%, "
                    << info.value("imageFormat").toString().toUpper() << Qt::endl;
            }
            return 0;
        }

        QString inputPath = parser.value(inputOpt);
        QString outputPath = parser.value(outputOpt);
        QString preset = parser.value(presetOpt);
        bool estimate = parser.isSet(estimateOpt);

        if (parser.isSet(guidedOpt)) {
            if (inputPath.isEmpty()) {
                out << "PDF input: " << Qt::flush;
                inputPath = in.readLine().trimmed();
            }
            if (!estimate && outputPath.isEmpty()) {
                out << "PDF output: " << Qt::flush;
                outputPath = in.readLine().trimmed();
            }
            out << "Preset [1=Senza Perdite, 2=Massima, 3=Standard, 4=Bassa]: " << Qt::flush;
            const QString choice = in.readLine().trimmed();
            if (choice == "1") preset = "lossless";
            else if (choice == "2") preset = "massima";
            else if (choice == "4") preset = "bassa";
            else preset = "standard";
            if (!estimate) {
                out << "Stimare prima la dimensione? [s/N]: " << Qt::flush;
                const QString answer = in.readLine().trimmed().toLower();
                if (answer == "s" || answer == "si" || answer == "y" || answer == "yes") {
                    const QVariantMap estimateRes = flattener.estimateWithPreset(inputPath, preset);
                    out << QJsonDocument(QJsonObject::fromVariantMap(estimateRes)).toJson(QJsonDocument::Compact) << Qt::endl;
                }
            }
        }

        QVariantMap result;
        if (inputPath.isEmpty()) {
            result = {{"success", false}, {"error", "Specificare --input."}};
        } else if (estimate) {
            if (parser.isSet(dpiOpt) || parser.isSet(qualityOpt) || parser.isSet(formatOpt)) {
                const QVariantMap defaults = flattener.presetInfo(preset);
                const int dpi = parser.isSet(dpiOpt) ? parser.value(dpiOpt).toInt() : defaults.value("dpi").toInt();
                const int quality = parser.isSet(qualityOpt) ? parser.value(qualityOpt).toInt() : defaults.value("quality").toInt();
                const QString format = parser.isSet(formatOpt) ? parser.value(formatOpt) : defaults.value("imageFormat").toString();
                result = flattener.estimateWithOptions(inputPath, dpi, quality, format);
            } else {
                result = flattener.estimateWithPreset(inputPath, preset);
            }
        } else if (outputPath.isEmpty()) {
            result = {{"success", false}, {"error", "Specificare --output."}};
        } else if (parser.isSet(dpiOpt) || parser.isSet(qualityOpt) || parser.isSet(formatOpt)) {
            const QVariantMap defaults = flattener.presetInfo(preset);
            const int dpi = parser.isSet(dpiOpt) ? parser.value(dpiOpt).toInt() : defaults.value("dpi").toInt();
            const int quality = parser.isSet(qualityOpt) ? parser.value(qualityOpt).toInt() : defaults.value("quality").toInt();
            const QString format = parser.isSet(formatOpt) ? parser.value(formatOpt) : defaults.value("imageFormat").toString();
            result = flattener.flattenWithOptions(inputPath, outputPath, dpi, quality, format, false);
        } else {
            result = flattener.flattenWithPreset(inputPath, outputPath, preset, false);
        }

        out << QJsonDocument(QJsonObject::fromVariantMap(result)).toJson(QJsonDocument::Compact) << Qt::endl;
        return result.value("success").toBool() ? 0 : 2;
    }

    QApplication app(argc, argv);
    QCoreApplication::setApplicationName(QStringLiteral("flatPDF"));
    QCoreApplication::setApplicationVersion(QStringLiteral("0.1"));
    QCoreApplication::setOrganizationName(QStringLiteral("Roberto Bissanti"));

    QQmlApplicationEngine engine;
    QMenuBar appMenuBar;
    QMenu* appMenu = appMenuBar.addMenu(QStringLiteral("flatPDF"));
    QAction* aboutAction = appMenu->addAction(QStringLiteral("Informazioni su flatPDF"));
    aboutAction->setMenuRole(QAction::AboutRole);
    QObject::connect(aboutAction, &QAction::triggered, []() {
#ifdef Q_OS_MACOS
        showNativeAboutPanel();
#else
        QMessageBox::about(nullptr,
                           QStringLiteral("Informazioni su flatPDF"),
                           QStringLiteral(
                               "<b>flatPDF</b><br>"
                               "Versione 0.1<br><br>"
                               "PDF flattener: PDF &rarr; immagini &rarr; PDF piatto.<br><br>"
                               "&copy; 2025-2026 Roberto Bissanti<br>"
                               "<a href=\"mailto:roberto.bissanti@gmail.com\">roberto.bissanti@gmail.com</a><br><br>"
                               "Licenza GPL v2"));
#endif
    });

    // Expose PdfFlattener as a singleton in the flatPdfQt2 module
    static PdfFlattener flattener;
    // Optional: set default working directory to Documents, as in the original code
    QDir::setCurrent(QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation));
    qmlRegisterSingletonInstance<PdfFlattener>("flatPdfQt2", 1, 0, "PdfFlattener", &flattener);
    QObject::connect(
        &engine,
        &QQmlApplicationEngine::objectCreationFailed,
        &app,
        []() { QCoreApplication::exit(-1); },
        Qt::QueuedConnection);
    engine.load(QUrl(QStringLiteral("qrc:/flatPdfQt2/Main.qml")));

    return app.exec();
}
