package com.olaf.sample

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.olaf.LogCategory
import com.olaf.Olaf
import com.olaf.OlafDecoding
import com.olaf.network.OlafMockResponse
import com.olaf.network.OlafNetwork
import com.olaf.network.installOlaf
import com.olaf.ui.OlafUI
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.MediaType.Companion.toMediaType

/** Demo host for the Olaf viewer: emits logs, makes real calls, and exercises mocking. */
class SampleActivity : ComponentActivity() {

    // The single line a host app adds to its own client.
    private val client = OkHttpClient.Builder()
        .installOlaf()
        .build()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MaterialTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    SampleScreen(client)
                }
            }
        }
    }
}

@Composable
private fun SampleScreen(client: OkHttpClient) {
    val scope = rememberCoroutineScope()

    fun call(url: String, body: String? = null) {
        scope.launch {
            withContext(Dispatchers.IO) {
                runCatching {
                    val builder = Request.Builder().url(url)
                    if (body != null) {
                        builder.post(body.toRequestBody("application/json".toMediaType()))
                    }
                    client.newCall(builder.build()).execute().use { it.body.string() }
                }.onFailure { Olaf.error(it, LogCategory.Network) }
            }
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        Text("Olaf", style = MaterialTheme.typography.headlineMedium)
        Text(
            text = "Shake the device to open the viewer.",
            style = MaterialTheme.typography.bodyMedium
        )

        Button(onClick = { OlafUI.present() }, modifier = Modifier.fillMaxWidth()) {
            Text("Open viewer")
        }

        Button(
            onClick = { call("https://postman-echo.com/get?olaf=demo") },
            modifier = Modifier.fillMaxWidth()
        ) { Text("GET request") }

        Button(
            onClick = { call("https://postman-echo.com/post", """{"amount":42,"currency":"EUR"}""") },
            modifier = Modifier.fillMaxWidth()
        ) { Text("POST request") }

        Button(
            onClick = { call("https://postman-echo.com/status/500") },
            modifier = Modifier.fillMaxWidth()
        ) { Text("Failing request (500)") }

        OutlinedButton(
            onClick = {
                OlafNetwork.addMock(
                    OlafMockResponse(
                        urlContains = "postman-echo.com/get",
                        json = """{"mocked":true,"accounts":[]}""",
                        statusCode = 418
                    )
                )
                Olaf.notice("Mock registered for /get", LogCategory.General)
            },
            modifier = Modifier.fillMaxWidth()
        ) { Text("Register a mock for GET") }

        OutlinedButton(
            onClick = {
                OlafNetwork.removeAllMocks()
                Olaf.notice("All mocks removed", LogCategory.General)
            },
            modifier = Modifier.fillMaxWidth()
        ) { Text("Remove mocks") }

        OutlinedButton(
            onClick = {
                // OlafDecoding logs the failure with its field path, then rethrows untouched.
                runCatching {
                    OlafDecoding.decode(
                        url = "https://postman-echo.com/get",
                        body = """{"iban": 42}""",
                        typeName = "Account"
                    ) {
                        throw IllegalStateException(
                            "Expected a string but was NUMBER at path \$.iban"
                        )
                    }
                }
            },
            modifier = Modifier.fillMaxWidth()
        ) { Text("Simulate a decoding error") }

        OutlinedButton(
            onClick = {
                Olaf.debug("A debug line", LogCategory.General)
                Olaf.info("Login succeeded", LogCategory.Auth, mapOf("method" to "biometric"))
                Olaf.warning("Cache miss", LogCategory.General)
                Olaf.error("Transfer declined", LogCategory.Payment, mapOf("code" to "INSUFFICIENT_FUNDS"))
                Olaf.trackScreen("dashboard")
            },
            modifier = Modifier.fillMaxWidth()
        ) { Text("Emit sample logs") }
    }
}
