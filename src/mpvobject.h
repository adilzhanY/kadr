#pragma once

#include <QQuickFramebufferObject>
#include <QtQml/qqmlregistration.h>

#include <mpv/client.h>
#include <mpv/render_gl.h>

#include <atomic>

class MpvObject : public QQuickFramebufferObject
{
    Q_OBJECT
    QML_ELEMENT
    Q_PROPERTY(double position READ position NOTIFY positionChanged)
    Q_PROPERTY(double duration READ duration NOTIFY durationChanged)
    Q_PROPERTY(bool pause READ pause WRITE setPause NOTIFY pauseChanged)
    Q_PROPERTY(double volume READ volume WRITE setVolume NOTIFY volumeChanged)
    Q_PROPERTY(bool mute READ mute WRITE setMute NOTIFY muteChanged)
    Q_PROPERTY(bool subVisible READ subVisible WRITE setSubVisible NOTIFY subVisibleChanged)
    Q_PROPERTY(QString mediaTitle READ mediaTitle NOTIFY mediaTitleChanged)

public:
    explicit MpvObject(QQuickItem *parent = nullptr);
    ~MpvObject() override;

    Renderer *createRenderer() const override;

    double position() const { return m_position; }
    double duration() const { return m_duration; }
    bool pause() const { return m_pause; }
    double volume() const { return m_volume; }
    bool mute() const { return m_mute; }
    bool subVisible() const { return m_subVisible; }
    QString mediaTitle() const { return m_mediaTitle; }

    void setPause(bool on);
    void setVolume(double vol);
    void setMute(bool on);
    void setSubVisible(bool on);

    // Frames mpv has asked us to render; a steady climb proves video flows.
    Q_INVOKABLE int updateCount() const { return m_updateCount.load(); }

    Q_INVOKABLE void loadFile(const QString &path);
    Q_INVOKABLE void togglePause() { setPause(!m_pause); }
    Q_INVOKABLE void seek(double pos);
    Q_INVOKABLE void seekBy(double secs);
    Q_INVOKABLE void command(const QStringList &args);

signals:
    void positionChanged();
    void durationChanged();
    void pauseChanged();
    void volumeChanged();
    void muteChanged();
    void subVisibleChanged();
    void mediaTitleChanged();
    void fileLoaded();

private:
    void handleEvents();
    void renderContextReady();
    void setMpvProperty(const char *name, const QVariant &value);

    mpv_handle *m_mpv = nullptr;
    mpv_render_context *m_renderCtx = nullptr;

    QString m_pendingFile;
    bool m_ctxReady = false;
    std::atomic<int> m_updateCount{0};
    double m_position = 0;
    double m_duration = 0;
    double m_volume = 100;
    bool m_pause = true;
    bool m_mute = false;
    bool m_subVisible = true;
    QString m_mediaTitle;

    friend class MpvRenderer;
};
