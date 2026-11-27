package com.g2ray.client.vpn

import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.Implementation
import org.robolectric.annotation.Implements
import org.robolectric.shadow.api.Shadow
import org.robolectric.shadows.ShadowNetwork
import org.robolectric.shadows.ShadowNetworkCapabilities

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [Build.VERSION_CODES.S])
class G2RayVpnServiceNetworkRegistrationTest {
    private var service: G2RayVpnService? = null

    @After
    fun tearDown() {
        service?.onDestroy()
        service = null
    }

    @Test
    fun androidSWaitsForBestMatchingPhysicalNetworkBeforeTunnelStartup() {
        val created = Robolectric.buildService(G2RayVpnService::class.java).create().get()
        service = created

        G2RayVpnService::class.java
            .getDeclaredMethod("registerUnderlyingNetworkMonitor")
            .apply { isAccessible = true }
            .invoke(created)

        val waiting = G2RayVpnService::class.java
            .getDeclaredField("waitingForUnderlyingNetwork")
            .apply { isAccessible = true }
            .getBoolean(created)

        assertTrue(waiting)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    @Config(shadows = [RegistrationFailureShadow::class])
    fun offlineRegistrationFallsBackToSnapshotsAndStopsPollingAfterCallbackRegisters() = runTest {
        physical = null
        allowRegistration = false
        registrations = 0
        val created = Robolectric.buildService(G2RayVpnService::class.java).create().get()
        service = created
        G2RayVpnService::class.java.getDeclaredField("scope").apply { isAccessible = true }
            .set(created, backgroundScope)
        fun invoke(method: String) {
            G2RayVpnService::class.java.getDeclaredMethod(method).apply { isAccessible = true }.invoke(created)
        }
        invoke("registerUnderlyingNetworkMonitor")
        runCurrent()
        assertNull(SocketProtector.underlyingNetworks.value)
        physical = ShadowNetwork.newInstance(101)
        advanceTimeBy(5_000)
        runCurrent()
        assertEquals(physical, SocketProtector.underlyingNetworks.value)
        allowRegistration = true
        physical = ShadowNetwork.newInstance(102)
        advanceTimeBy(5_000)
        runCurrent()
        assertEquals(physical, SocketProtector.underlyingNetworks.value)
        assertEquals(3, registrations)
        advanceTimeBy(15_000)
        runCurrent()
        assertEquals(3, registrations)
        invoke("unregisterUnderlyingNetworkMonitor")
        assertNull(SocketProtector.underlyingNetworks.value)
    }

    @Implements(ConnectivityManager::class)
    @Suppress("UNUSED_PARAMETER")
    class RegistrationFailureShadow {
        @Implementation
        fun registerBestMatchingNetworkCallback(
            request: NetworkRequest, callback: ConnectivityManager.NetworkCallback, handler: Handler
        ) {
            throw IllegalStateException("Best matching callback unavailable")
        }

        @Implementation
        fun registerNetworkCallback(request: NetworkRequest, callback: ConnectivityManager.NetworkCallback) {
            registrations++
            check(allowRegistration)
        }

        @Implementation
        fun getAllNetworks(): Array<Network> = listOfNotNull(physical).toTypedArray()

        @Implementation
        fun getNetworkCapabilities(network: Network): NetworkCapabilities? =
            if (network != physical) null else NetworkCapabilities().also {
                val shadow = Shadow.extract<ShadowNetworkCapabilities>(it)
                shadow.addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                shadow.addCapability(NetworkCapabilities.NET_CAPABILITY_NOT_VPN)
            }

        @Implementation
        fun unregisterNetworkCallback(callback: ConnectivityManager.NetworkCallback) = Unit
    }

    companion object {
        private var registrations = 0
        private var allowRegistration = false
        private var physical: Network? = null
    }
}
