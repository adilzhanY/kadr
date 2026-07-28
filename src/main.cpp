#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>

#include <clocale>

int main(int argc, char *argv[])
{
    // libmpv renders through the OpenGL render API; force the matching RHI backend.
    QQuickWindow::setGraphicsApi(QSGRendererInterface::OpenGL);

    QGuiApplication app(argc, argv);
    QGuiApplication::setApplicationName(QStringLiteral("kadr"));
    QGuiApplication::setDesktopFileName(QStringLiteral("kadr"));

    // libmpv requires the C numeric locale; Qt may have changed it above.
    std::setlocale(LC_NUMERIC, "C");

    const QStringList args = app.arguments();
    const QString file = args.size() > 1 ? args.at(1) : QString();

    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("cliFile"), file);
    engine.rootContext()->setContextProperty(
        QStringLiteral("smokeTest"), qEnvironmentVariableIsSet("KADR_SMOKE"));
    engine.rootContext()->setContextProperty(
        QStringLiteral("shotPath"), qEnvironmentVariable("KADR_SHOT"));
    engine.rootContext()->setContextProperty(
        QStringLiteral("holdControls"), qEnvironmentVariableIsSet("KADR_HOLD_CONTROLS"));
    engine.rootContext()->setContextProperty(
        QStringLiteral("envTheme"), qEnvironmentVariable("KADR_THEME"));

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed, &app,
                     [] { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule(QStringLiteral("Kadr"), QStringLiteral("Main"));

    return app.exec();
}
