#include "theme.h"

#include <QColor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QStandardPaths>

Theme::Theme(QObject *parent)
    : QObject(parent)
{
    m_path = QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation)
             + QStringLiteral("/quickshell/user/generated/colors.json");
    load();
    rearm();
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { load(); rearm(); });
    // matugen replaces the file atomically, which drops the inode watch;
    // the directory watch picks the new file back up.
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { load(); rearm(); });
}

void Theme::rearm()
{
    const QStringList watched = m_watcher.files() + m_watcher.directories();
    if (!watched.isEmpty())
        m_watcher.removePaths(watched);
    if (QFileInfo::exists(m_path))
        m_watcher.addPath(m_path);
    m_watcher.addPath(QFileInfo(m_path).dir().path());
}

void Theme::load()
{
    QFile f(m_path);
    if (!f.open(QIODevice::ReadOnly))
        return;

    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isObject())
        return;

    QVariantMap next = doc.object().toVariantMap();
    if (next == m_colors)
        return;

    m_colors = next;
    const QColor bg(m_colors.value(QStringLiteral("background")).toString());
    m_dark = bg.isValid() && bg.lightnessF() < 0.5;
    emit colorsChanged();
}

QColor Theme::color(const QString &name, const QColor &fallback) const
{
    const QColor c(m_colors.value(name).toString());
    return c.isValid() ? c : fallback;
}
