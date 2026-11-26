package com.g2ray.client.vpn

import android.content.Context
import android.os.SystemClock
import com.g2ray.client.G2RayApplication
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.HttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody
import okhttp3.RequestBody.Companion.toRequestBody
import okio.BufferedSink
import org.json.JSONObject
import org.junit.Assert.*
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

private data class OwnedFixture(val base: HttpUrl, val token: String, val config: JSONObject)

private fun requireTunneledHost(context: Context, host: String) {
    val settings = VpnEnginePreferences((context.applicationContext as G2RayApplication).secureStore).readSettings()
    require(settings.routingPolicy.bypassDomains.none { host == it || host.endsWith(".$it") }) {
        "The test endpoint matches a direct-routing bypass rule"
    }
}

private fun readOwnedFixture(context: Context, record: (String) -> Unit): OwnedFixture {
    val fixture = JSONObject(File(context.filesDir, "integrity-fixture.private.json").readText())
    val base = fixture.getString("base_url").toHttpUrl()
    require(base.isHttps && base.port == 443 && base.host.endsWith(".app.github.dev") &&
        base.encodedPath == "/" && base.query == null && base.username.isEmpty() && base.password.isEmpty())
    requireTunneledHost(context, base.host)
    record("event=owned_fixture_route proxy_required=true no_matching_domain_bypass=true")
    val token = fixture.getString("token")
    require(token.matches(Regex("[a-f0-9]{64}")))
    return OwnedFixture(base, token, fixture)
}

/** An explicitly provisioned owned fixture, not a public speed-test assumption. */
internal fun verifySyntheticIntegrity(context: Context, client: OkHttpClient, record: (String) -> Unit) {
    val (base, token, fixture) = readOwnedFixture(context, record)
    val samples = fixture.getInt("samples").also { require(it in 1..5) }
    val chunk = ByteArray(32768) { ((it * 31 + 17) % 251).toByte() }
    fun digest(length: Int): String {
        val hash = MessageDigest.getInstance("SHA-256")
        var remaining = length
        while (remaining > 0) {
            val count = minOf(remaining, chunk.size)
            hash.update(chunk, 0, count)
            remaining -= count
        }
        return hash.digest().joinToString("") { "%02x".format(it) }
    }
    val failed = mutableListOf<String>()
    for (sample in 0 until samples) {
        for (direction in listOf("download", "upload")) {
            val size = if (direction == "download") 8 * 1024 * 1024 else 2 * 1024 * 1024
            val expected = digest(size)
            val started = SystemClock.elapsedRealtime()
            var bytes = 0L
            val row = JSONObject().put("event", "owned_integrity").put("sample", sample).put("direction", direction)
            try {
                val request = Request.Builder().header("Authorization", "Bearer $token")
                    .header("Accept-Encoding", "identity").header("Cache-Control", "no-store")
                if (direction == "download") {
                    request.url(base.newBuilder().addPathSegment("download").addQueryParameter("bytes", size.toString()).build())
                    client.newCall(request.build()).execute().use { response ->
                        row.put("headers_ms", SystemClock.elapsedRealtime() - started).put("protocol", response.protocol.toString())
                        assertEquals(200, response.code)
                        assertEquals(expected, response.header("X-Content-SHA256"))
                        val body = requireNotNull(response.body)
                        assertEquals(size.toLong(), body.contentLength())
                        val hash = MessageDigest.getInstance("SHA-256")
                        val buffer = ByteArray(32768)
                        body.byteStream().use { stream ->
                            while (true) {
                                val count = stream.read(buffer)
                                if (count < 0) break
                                bytes += count
                                require(bytes <= size) { "Oversized synthetic response" }
                                hash.update(buffer, 0, count)
                            }
                        }
                        assertEquals(size.toLong(), bytes)
                        assertEquals(expected, hash.digest().joinToString("") { "%02x".format(it) })
                    }
                } else {
                    val body = object : RequestBody() {
                        override fun contentType() = "application/octet-stream".toMediaType()
                        override fun contentLength() = size.toLong()
                        override fun isOneShot() = true
                        override fun writeTo(sink: BufferedSink) {
                            var remaining = size
                            while (remaining > 0) {
                                val count = minOf(remaining, chunk.size)
                                sink.write(chunk, 0, count)
                                bytes += count
                                remaining -= count
                            }
                        }
                    }
                    request.url(base.newBuilder().addPathSegment("upload").build())
                        .header("X-Content-SHA256", expected).post(body)
                    client.newCall(request.build()).execute().use { response ->
                        row.put("headers_ms", SystemClock.elapsedRealtime() - started).put("protocol", response.protocol.toString())
                        assertEquals(200, response.code)
                        val responseBody = requireNotNull(response.body)
                        require(responseBody.contentLength() in 1..1024) { "Unexpected integrity receipt length" }
                        val reply = JSONObject(responseBody.string())
                        assertEquals(size.toLong(), reply.getLong("bytes"))
                        assertTrue(reply.getBoolean("matched"))
                        assertEquals(expected, reply.getString("sha256"))
                        assertEquals(size.toLong(), bytes)
                    }
                }
                row.put("verified_hash", true)
            } catch (error: Exception) {
                failed += "$sample/$direction/${error.javaClass.simpleName}"
                row.put("verified_hash", false).put("error", error.javaClass.simpleName)
            } catch (error: AssertionError) {
                failed += "$sample/$direction/AssertionError"
                row.put("verified_hash", false).put("error", "AssertionError")
            } finally {
                row.put("bytes", bytes).put("elapsed_ms", SystemClock.elapsedRealtime() - started)
                record(row.toString())
            }
        }
    }
    assertTrue("Owned integrity failures: ${failed.joinToString()}", failed.isEmpty())
}

internal fun verifySyntheticEventStream(context: Context, client: OkHttpClient, record: (String) -> Unit) {
    val (base, token) = readOwnedFixture(context, record)
    val streamClient = client.newBuilder().retryOnConnectionFailure(false).followRedirects(false)
        .readTimeout(30L, TimeUnit.SECONDS).callTimeout(125L, TimeUnit.SECONDS).build()
    val request = Request.Builder().url(base.newBuilder().addPathSegment("stream").build())
        .header("Authorization", "Bearer $token")
        .header("Accept-Encoding", "identity")
        .post("""{"prompt":"synthetic stream test"}""".toRequestBody("application/json".toMediaType()))
        .build()
    val started = SystemClock.elapsedRealtime()
    streamClient.newCall(request).execute().use { response ->
        assertEquals(200, response.code)
        val body = requireNotNull(response.body)
        assertEquals("text/event-stream", body.contentType()?.toString())
        val source = body.source()
        val observed = (0..9).map { index ->
            assertEquals(if (index == 9) "data: [DONE]" else "data: delta-$index", source.readUtf8LineStrict(80L))
            assertEquals("", source.readUtf8LineStrict(2L))
            val elapsed = SystemClock.elapsedRealtime() - started
            record("event=owned_sse_event index=$index elapsed_ms=$elapsed")
            elapsed
        }
        assertTrue("Unexpected bytes after the final event", source.exhausted())
        assertTrue("The first event arrived too late for interactive streaming", observed.first() in 5_000L..15_000L)
        assertTrue("The response was buffered instead of streamed", observed.last() - observed.first() >= 70_000L)
        assertTrue("The deliberately quiet gap was not observed", observed[4] - observed[3] >= 12_000L)
        record("event=owned_sse_complete events=10 final_marker=true first_ms=${observed.first()} total_ms=${observed.last()}")
    }
}

/** Check one real, continuous SSE connection without deploying a public test port. */
internal fun verifyPublicEventStream(context: Context, client: OkHttpClient, record: (String) -> Unit) {
    val endpoint = "https://stream.wikimedia.org/v2/stream/recentchange".toHttpUrl()
    requireTunneledHost(context, endpoint.host)
    val streamClient = client.newBuilder().retryOnConnectionFailure(false).followRedirects(false)
        .readTimeout(20L, TimeUnit.SECONDS).callTimeout(155L, TimeUnit.SECONDS).build()
    val request = Request.Builder().url(endpoint).header("Accept", "text/event-stream")
        .header("Accept-Encoding", "identity")
        .header("User-Agent", "G2RayAndroidAcceptance/1.0 (https://github.com/z2roozsh/G2rayXCodeLeafy)")
        .build()
    val started = SystemClock.elapsedRealtime()
    streamClient.newCall(request).execute().use { response ->
        assertEquals(200, response.code)
        val body = requireNotNull(response.body)
        assertEquals("text/event-stream", body.contentType()?.let { "${it.type}/${it.subtype}" })
        val source = body.source()
        var bytes = 0L
        var completeEvents = 0
        var firstEvent = -1L
        var lastEvent = -1L
        var maxEventGap = 0L
        var hasData = false
        do {
            val line = source.readUtf8LineStrict(32_768L)
            bytes += line.toByteArray(Charsets.UTF_8).size + 1
            require(bytes <= 8L * 1024 * 1024) { "Public SSE exceeded the 8 MiB data budget" }
            if (line.startsWith("data:") && line.substring(5).isNotBlank()) hasData = true
            if (line.isEmpty() && hasData) {
                val now = SystemClock.elapsedRealtime() - started
                if (firstEvent < 0L) firstEvent = now
                if (lastEvent >= 0L) maxEventGap = maxOf(maxEventGap, now - lastEvent)
                lastEvent = now
                completeEvents++
                hasData = false
            }
        } while (firstEvent < 0L || lastEvent - firstEvent < 120_000L)
        assertTrue("No prompt complete event", firstEvent in 1L..15_000L)
        assertTrue("Too few events to establish sustained delivery", completeEvents >= 20)
        record("event=public_sse_complete events=$completeEvents bytes=$bytes first_ms=$firstEvent " +
            "stream_ms=${lastEvent - firstEvent} max_event_gap_ms=$maxEventGap protocol=${response.protocol}")
    }
}
