#include "mpvobject.h"

#include <QOpenGLContext>
#include <QOpenGLFramebufferObject>
#include <QQuickOpenGLUtils>
#include <QQuickWindow>

#include <stdexcept>

namespace {

void *glProcAddress(void *, const char *name)
{
    QOpenGLContext *ctx = QOpenGLContext::currentContext();
    return ctx ? reinterpret_cast<void *>(ctx->getProcAddress(name)) : nullptr;
}

} // namespace

class MpvRenderer : public QQuickFramebufferObject::Renderer
{
public:
    explicit MpvRenderer(MpvObject *obj) : m_obj(obj) {}

    QOpenGLFramebufferObject *createFramebufferObject(const QSize &size) override
    {
        // The render context can only be created once a GL context is current.
        if (!m_obj->m_renderCtx) {
            mpv_opengl_init_params glInit{glProcAddress, nullptr};
            mpv_render_param params[]{
                {MPV_RENDER_PARAM_API_TYPE, const_cast<char *>(MPV_RENDER_API_TYPE_OPENGL)},
                {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &glInit},
                {MPV_RENDER_PARAM_INVALID, nullptr},
            };
            if (mpv_render_context_create(&m_obj->m_renderCtx, m_obj->m_mpv, params) < 0)
                throw std::runtime_error("kadr: failed to create mpv render context");
            mpv_render_context_set_update_callback(
                m_obj->m_renderCtx,
                [](void *ctx) {
                    auto *obj = static_cast<MpvObject *>(ctx);
                    obj->m_updateCount.fetch_add(1);
                    QMetaObject::invokeMethod(obj, [obj] { obj->update(); }, Qt::QueuedConnection);
                },
                m_obj);
            // Playback must not start before this context exists, or mpv
            // drops the video track ("No render context set").
            MpvObject *obj = m_obj;
            QMetaObject::invokeMethod(obj, [obj] { obj->renderContextReady(); }, Qt::QueuedConnection);
        }
        return QQuickFramebufferObject::Renderer::createFramebufferObject(size);
    }

    void render() override
    {
        QOpenGLFramebufferObject *fbo = framebufferObject();
        mpv_opengl_fbo mpvFbo{static_cast<int>(fbo->handle()), fbo->width(), fbo->height(), 0};
        int flipY = 0;
        mpv_render_param params[]{
            {MPV_RENDER_PARAM_OPENGL_FBO, &mpvFbo},
            {MPV_RENDER_PARAM_FLIP_Y, &flipY},
            {MPV_RENDER_PARAM_INVALID, nullptr},
        };
        mpv_render_context_render(m_obj->m_renderCtx, params);
        QQuickOpenGLUtils::resetOpenGLState();
    }

private:
    MpvObject *m_obj;
};

MpvObject::MpvObject(QQuickItem *parent)
    : QQuickFramebufferObject(parent)
{
    m_mpv = mpv_create();
    if (!m_mpv)
        throw std::runtime_error("kadr: failed to create mpv instance");

    mpv_set_option_string(m_mpv, "terminal", "no");
    mpv_set_option_string(m_mpv, "msg-level", "all=warn");
    // Render into our FBO via the render API; without this mpv opens its own window.
    mpv_set_option_string(m_mpv, "vo", "libmpv");
    mpv_set_option_string(m_mpv, "force-window", "no");

    if (mpv_initialize(m_mpv) < 0)
        throw std::runtime_error("kadr: failed to initialize mpv");

    mpv_set_option_string(m_mpv, "hwdec", "auto-safe");
    mpv_set_option_string(m_mpv, "keep-open", "yes");

    // Same subtitle look the mentalist script used, rendered by libass.
    mpv_set_option_string(m_mpv, "sub-font", "SF Pro Rounded");
    mpv_set_option_string(m_mpv, "sub-font-size", "44");
    mpv_set_option_string(m_mpv, "sub-border-size", "2.2");
    mpv_set_option_string(m_mpv, "sub-color", "#FFFFFF");
    mpv_set_option_string(m_mpv, "sub-border-color", "#CC000000");
    mpv_set_option_string(m_mpv, "sub-pos", "94");

    mpv_request_log_messages(m_mpv, "warn");

    mpv_observe_property(m_mpv, 0, "time-pos", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "duration", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "pause", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, 0, "volume", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "speed", MPV_FORMAT_DOUBLE);
    mpv_observe_property(m_mpv, 0, "mute", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, 0, "sub-visibility", MPV_FORMAT_FLAG);
    mpv_observe_property(m_mpv, 0, "media-title", MPV_FORMAT_STRING);

    mpv_set_wakeup_callback(
        m_mpv,
        [](void *ctx) {
            auto *obj = static_cast<MpvObject *>(ctx);
            QMetaObject::invokeMethod(obj, [obj] { obj->handleEvents(); }, Qt::QueuedConnection);
        },
        this);
}

MpvObject::~MpvObject()
{
    if (m_renderCtx)
        mpv_render_context_free(m_renderCtx);
    mpv_terminate_destroy(m_mpv);
}

QQuickFramebufferObject::Renderer *MpvObject::createRenderer() const
{
    window()->setPersistentSceneGraph(true);
    return new MpvRenderer(const_cast<MpvObject *>(this));
}

void MpvObject::loadFile(const QString &path)
{
    if (!m_ctxReady) {
        m_pendingFile = path;
        return;
    }
    command({QStringLiteral("loadfile"), path});
}

void MpvObject::renderContextReady()
{
    m_ctxReady = true;
    if (!m_pendingFile.isEmpty()) {
        command({QStringLiteral("loadfile"), m_pendingFile});
        m_pendingFile.clear();
    }
}

void MpvObject::seek(double pos)
{
    command({QStringLiteral("seek"), QString::number(pos), QStringLiteral("absolute")});
}

void MpvObject::seekBy(double secs)
{
    command({QStringLiteral("seek"), QString::number(secs), QStringLiteral("relative")});
}

void MpvObject::command(const QStringList &args)
{
    QList<QByteArray> utf8;
    utf8.reserve(args.size());
    QVector<const char *> argv;
    argv.reserve(args.size() + 1);
    for (const QString &arg : args) {
        utf8.append(arg.toUtf8());
        argv.append(utf8.last().constData());
    }
    argv.append(nullptr);
    mpv_command_async(m_mpv, 0, argv.data());
}

void MpvObject::setPause(bool on)
{
    setMpvProperty("pause", on);
}

void MpvObject::setVolume(double vol)
{
    setMpvProperty("volume", qBound(0.0, vol, 130.0));
}

void MpvObject::setSpeed(double speed)
{
    setMpvProperty("speed", qBound(0.25, speed, 4.0));
}

void MpvObject::setMute(bool on)
{
    setMpvProperty("mute", on);
}

void MpvObject::setSubVisible(bool on)
{
    setMpvProperty("sub-visibility", on);
}

void MpvObject::setMpvProperty(const char *name, const QVariant &value)
{
    switch (value.typeId()) {
    case QMetaType::Bool: {
        int flag = value.toBool() ? 1 : 0;
        mpv_set_property_async(m_mpv, 0, name, MPV_FORMAT_FLAG, &flag);
        break;
    }
    case QMetaType::Double: {
        double d = value.toDouble();
        mpv_set_property_async(m_mpv, 0, name, MPV_FORMAT_DOUBLE, &d);
        break;
    }
    default: {
        QByteArray s = value.toString().toUtf8();
        mpv_set_property_string(m_mpv, name, s.constData());
        break;
    }
    }
}

void MpvObject::handleEvents()
{
    while (true) {
        mpv_event *event = mpv_wait_event(m_mpv, 0);
        if (event->event_id == MPV_EVENT_NONE)
            break;

        switch (event->event_id) {
        case MPV_EVENT_FILE_LOADED:
            emit fileLoaded();
            break;
        case MPV_EVENT_LOG_MESSAGE: {
            auto *msg = static_cast<mpv_event_log_message *>(event->data);
            qWarning("mpv [%s] %s", msg->prefix, QByteArray(msg->text).trimmed().constData());
            break;
        }
        case MPV_EVENT_PROPERTY_CHANGE: {
            auto *prop = static_cast<mpv_event_property *>(event->data);
            if (!prop->data)
                break;
            const QByteArray name(prop->name);
            if (name == "time-pos" && prop->format == MPV_FORMAT_DOUBLE) {
                m_position = *static_cast<double *>(prop->data);
                emit positionChanged();
            } else if (name == "duration" && prop->format == MPV_FORMAT_DOUBLE) {
                m_duration = *static_cast<double *>(prop->data);
                emit durationChanged();
            } else if (name == "pause" && prop->format == MPV_FORMAT_FLAG) {
                m_pause = *static_cast<int *>(prop->data);
                emit pauseChanged();
            } else if (name == "volume" && prop->format == MPV_FORMAT_DOUBLE) {
                m_volume = *static_cast<double *>(prop->data);
                emit volumeChanged();
            } else if (name == "speed" && prop->format == MPV_FORMAT_DOUBLE) {
                m_speed = *static_cast<double *>(prop->data);
                emit speedChanged();
            } else if (name == "mute" && prop->format == MPV_FORMAT_FLAG) {
                m_mute = *static_cast<int *>(prop->data);
                emit muteChanged();
            } else if (name == "sub-visibility" && prop->format == MPV_FORMAT_FLAG) {
                m_subVisible = *static_cast<int *>(prop->data);
                emit subVisibleChanged();
            } else if (name == "media-title" && prop->format == MPV_FORMAT_STRING) {
                m_mediaTitle = QString::fromUtf8(*static_cast<char **>(prop->data));
                emit mediaTitleChanged();
            }
            break;
        }
        default:
            break;
        }
    }
}
