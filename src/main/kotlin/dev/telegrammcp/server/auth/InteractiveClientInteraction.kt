package dev.telegrammcp.server.auth

import dev.telegrammcp.server.util.StructuredLogger
import it.tdlight.client.ClientInteraction
import it.tdlight.client.InputParameter
import it.tdlight.client.ParameterInfo
import it.tdlight.client.ParameterInfoCode
import java.util.concurrent.CompletableFuture

/**
 * [ClientInteraction] implementation that bridges TDLib auth prompts to the HTTP-based
 * wizard UI via [TelegramAuthStateHolder].
 *
 * Instead of reading from stdin, this implementation:
 * 1. Updates the [AuthState] in the holder (so the wizard can poll it).
 * 2. Returns a [CompletableFuture] that blocks TDLib until the wizard submits the value
 *    via the `/auth/submit-code` or `/auth/submit-password` endpoint.
 */
class InteractiveClientInteraction(
    private val authStateHolder: TelegramAuthStateHolder,
    private val phoneNumber: String,
) : ClientInteraction {

    private val log = StructuredLogger.forClass<InteractiveClientInteraction>()

    override fun onParameterRequest(
        parameter: InputParameter,
        info: ParameterInfo,
    ): CompletableFuture<String> = when (parameter) {
        InputParameter.ASK_CODE -> {
            // TDLib hands us the delivery channel here and nowhere else; it used
            // to be dropped, leaving the wizard unable to say where the code went.
            val codeInfo = info as? ParameterInfoCode
            val channel = AuthCodeChannel.of(codeInfo?.type)
            log.info("TDLib requests login code (channel={}) — waiting for interactive input", channel ?: "unknown")
            authStateHolder.setState(
                AuthState.WaitingCode(
                    phoneNumber = codeInfo?.phoneNumber?.takeIf { it.isNotBlank() } ?: phoneNumber,
                    codeChannel = channel,
                    nextCodeChannel = AuthCodeChannel.of(codeInfo?.nextType),
                    resendTimeoutSeconds = codeInfo?.timeout?.takeIf { it > 0 },
                ),
            )
            authStateHolder.awaitCode()
        }

        InputParameter.ASK_PASSWORD -> {
            log.info("TDLib requests 2FA password — waiting for interactive input")
            authStateHolder.setState(AuthState.WaitingPassword())
            authStateHolder.awaitPassword()
        }

        InputParameter.NOTIFY_LINK -> {
            log.info("TDLib NOTIFY_LINK received")
            // QR link is extracted from UpdateAuthorizationState in the orchestrator
            CompletableFuture.completedFuture("")
        }

        InputParameter.TERMS_OF_SERVICE -> {
            log.info("Automatically accepting Terms of Service")
            CompletableFuture.completedFuture("Y")
        }

        else -> {
            log.warn("Unhandled interactive parameter request: {} — returning empty", parameter)
            CompletableFuture.completedFuture("")
        }
    }
}
