package com.touchcontroller.mobile_client

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.os.Build
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.DataInputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.touchcontroller.mobile_client/audio"

    private var audioThread: Thread? = null
    @Volatile private var isStreaming = false
    @Volatile private var socketConnected = false
    @Volatile private var bytesReceived: Long = 0L
    @Volatile private var lastError: String = ""
    private var audioTrack: AudioTrack? = null
    private var clientSocket: Socket? = null
    private var currentVolume = 1.0f
    private var focusRequest: AudioFocusRequest? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startAudio" -> {
                    val host = call.argument<String>("host") ?: "127.0.0.1"
                    val port = call.argument<Int>("port") ?: 8891
                    val success = startAudioStream(host, port)
                    result.success(success)
                }
                "stopAudio" -> {
                    stopAudioStream()
                    result.success(true)
                }
                "setVolume" -> {
                    val vol = (call.argument<Double>("volume") ?: 1.0).toFloat()
                    setAudioVolume(vol)
                    result.success(true)
                }
                "isStreaming" -> {
                    result.success(isStreaming)
                }
                "getAudioState" -> {
                    result.success(
                        mapOf(
                            "isStreaming" to isStreaming,
                            "socketConnected" to socketConnected,
                            "bytesReceived" to bytesReceived,
                            "lastError" to lastError
                        )
                    )
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun requestMediaAudioFocus() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            val curVol = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
            val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
            if (curVol == 0 && maxVol > 0) {
                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, (maxVol * 0.70).toInt(), 0)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                val attrs = AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                    .build()
                val req = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                    .setAudioAttributes(attrs)
                    .setOnAudioFocusChangeListener { }
                    .build()
                focusRequest = req
                audioManager.requestAudioFocus(req)
            } else {
                @Suppress("DEPRECATION")
                audioManager.requestAudioFocus(null, AudioManager.STREAM_MUSIC, AudioManager.AUDIOFOCUS_GAIN)
            }
        } catch (_: Exception) {}
    }

    private fun abandonMediaAudioFocus() {
        try {
            val audioManager = getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
            } else {
                @Suppress("DEPRECATION")
                audioManager.abandonAudioFocus(null)
            }
        } catch (_: Exception) {}
    }

    private fun createAudioTrack(sampleRate: Int, channels: Int): AudioTrack {
        val channelConfig = if (channels <= 1) AudioFormat.CHANNEL_OUT_MONO else AudioFormat.CHANNEL_OUT_STEREO
        val audioFormat = AudioFormat.ENCODING_PCM_16BIT
        val minBuf = AudioTrack.getMinBufferSize(sampleRate, channelConfig, audioFormat)
        val bufferSize = Math.max(minBuf, 3840 * 4)

        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()

        val format = AudioFormat.Builder()
            .setEncoding(audioFormat)
            .setSampleRate(sampleRate)
            .setChannelMask(channelConfig)
            .build()

        val track = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            AudioTrack.Builder()
                .setAudioAttributes(attributes)
                .setAudioFormat(format)
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STREAM)
                .setPerformanceMode(AudioTrack.PERFORMANCE_MODE_LOW_LATENCY)
                .build()
        } else {
            @Suppress("DEPRECATION")
            AudioTrack(
                AudioManager.STREAM_MUSIC,
                sampleRate,
                channelConfig,
                audioFormat,
                bufferSize,
                AudioTrack.MODE_STREAM
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            track.setVolume(currentVolume)
        } else {
            @Suppress("DEPRECATION")
            track.setStereoVolume(currentVolume, currentVolume)
        }
        return track
    }

    @Synchronized
    private fun startAudioStream(host: String, port: Int): Boolean {
        if (isStreaming) {
            stopAudioStream()
        }

        isStreaming = true
        socketConnected = false
        bytesReceived = 0L
        lastError = ""
        requestMediaAudioFocus()

        audioThread = Thread({
            Process.setThreadPriority(Process.THREAD_PRIORITY_URGENT_AUDIO)

            val sizeBuf = ByteArray(4)
            val pcmBuffer = ByteArray(65536)

            while (isStreaming) {
                var sock: Socket? = null
                try {
                    sock = Socket()
                    sock.tcpNoDelay = true
                    sock.receiveBufferSize = 3840 * 8
                    sock.connect(InetSocketAddress(host, port), 3000)
                    clientSocket = sock

                    val input = DataInputStream(sock.getInputStream())

                    // Read 16-byte handshake header
                    val headerBytes = ByteArray(16)
                    input.readFully(headerBytes)

                    val magic = String(headerBytes, 0, 8)
                    if (!magic.startsWith("KL_AUDIO")) {
                        lastError = "Invalid header: $magic"
                        android.util.Log.e("AudioRelay", lastError)
                        break
                    }

                    val hdrBuf = ByteBuffer.wrap(headerBytes).order(ByteOrder.LITTLE_ENDIAN)
                    val sampleRate = hdrBuf.getInt(10).let { if (it in 8000..192000) it else 48000 }
                    val channels = (headerBytes[14].toInt() and 0xFF).let { if (it in 1..2) it else 2 }

                    cleanupAudioTrack()
                    val track = createAudioTrack(sampleRate, channels)
                    audioTrack = track
                    track.play()

                    socketConnected = true
                    lastError = ""
                    android.util.Log.i("AudioRelay", "Connected to $host:$port (${sampleRate}Hz, ${channels}ch)")

                    while (isStreaming && !sock.isClosed) {
                        input.readFully(sizeBuf)
                        val chunkSize = ByteBuffer.wrap(sizeBuf).order(ByteOrder.LITTLE_ENDIAN).int
                        if (chunkSize <= 0 || chunkSize > pcmBuffer.size) {
                            break
                        }

                        input.readFully(pcmBuffer, 0, chunkSize)
                        bytesReceived += chunkSize.toLong()

                        if (isStreaming && audioTrack != null) {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                                audioTrack?.write(pcmBuffer, 0, chunkSize, AudioTrack.WRITE_BLOCKING)
                            } else {
                                audioTrack?.write(pcmBuffer, 0, chunkSize)
                            }
                        }
                    }
                } catch (e: Exception) {
                    lastError = e.message ?: "Connection lost"
                    android.util.Log.w("AudioRelay", "Connection blip: $lastError")
                } finally {
                    socketConnected = false
                    cleanupAudioTrack()
                    try {
                        sock?.close()
                    } catch (_: Exception) {}
                    clientSocket = null
                }

                if (isStreaming) {
                    try {
                        Thread.sleep(700)
                    } catch (_: InterruptedException) {
                        break
                    }
                }
            }
        }, "KernalLinkAudioThread")

        audioThread?.start()
        return true
    }

    @Synchronized
    private fun stopAudioStream() {
        isStreaming = false
        socketConnected = false
        try {
            clientSocket?.close()
        } catch (_: Exception) {}
        clientSocket = null

        cleanupAudioTrack()
        abandonMediaAudioFocus()

        try {
            audioThread?.interrupt()
            audioThread?.join(500)
        } catch (_: Exception) {}
        audioThread = null
    }

    @Synchronized
    private fun cleanupAudioTrack() {
        try {
            audioTrack?.pause()
            audioTrack?.flush()
            audioTrack?.stop()
            audioTrack?.release()
        } catch (_: Exception) {}
        audioTrack = null
    }

    private fun setAudioVolume(volume: Float) {
        currentVolume = volume.coerceIn(0.0f, 1.0f)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            audioTrack?.setVolume(currentVolume)
        } else {
            @Suppress("DEPRECATION")
            audioTrack?.setStereoVolume(currentVolume, currentVolume)
        }
    }

    override fun onDestroy() {
        stopAudioStream()
        super.onDestroy()
    }
}
