#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// Watches the palette matugen writes on every wallpaper/theme change and
// exposes it to QML, so kadr recolors live like the rest of the desktop.
class Theme : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON
    Q_PROPERTY(QVariantMap colors READ colors NOTIFY colorsChanged)
    Q_PROPERTY(bool dark READ dark NOTIFY colorsChanged)

public:
    explicit Theme(QObject *parent = nullptr);

    QVariantMap colors() const { return m_colors; }
    bool dark() const { return m_dark; }

    Q_INVOKABLE QColor color(const QString &name, const QColor &fallback) const;

signals:
    void colorsChanged();

private:
    void load();
    void rearm();

    QString m_path;
    QVariantMap m_colors;
    bool m_dark = false;
    QFileSystemWatcher m_watcher;
};
