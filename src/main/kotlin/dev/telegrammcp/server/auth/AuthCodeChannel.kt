package dev.telegrammcp.server.auth

import it.tdlight.jni.TdApi

/**
 * Where Telegram put the login code.
 *
 * Telegram picks the channel itself: an account with another active session
 * gets the code inside the Telegram app, a lone account gets an SMS, and in
 * several countries it arrives as a call — where for a flash/missed call the
 * *caller's number* is the code, and no message is ever delivered. A wizard
 * that only says "enter the code" therefore sends people hunting through the
 * wrong inbox, which is exactly what happened before this was surfaced.
 *
 * Values are stable machine identifiers; phrasing them for a human is the
 * client's job.
 */
object AuthCodeChannel {

    fun of(type: TdApi.AuthenticationCodeType?): String? = when (type) {
        null -> null
        is TdApi.AuthenticationCodeTypeTelegramMessage -> "telegramApp"
        is TdApi.AuthenticationCodeTypeSms -> "sms"
        is TdApi.AuthenticationCodeTypeSmsWord -> "smsWord"
        is TdApi.AuthenticationCodeTypeSmsPhrase -> "smsPhrase"
        is TdApi.AuthenticationCodeTypeCall -> "call"
        is TdApi.AuthenticationCodeTypeFlashCall -> "flashCall"
        is TdApi.AuthenticationCodeTypeMissedCall -> "missedCall"
        is TdApi.AuthenticationCodeTypeFragment -> "fragment"
        is TdApi.AuthenticationCodeTypeFirebaseAndroid -> "firebase"
        is TdApi.AuthenticationCodeTypeFirebaseIos -> "firebase"
        // A channel added by a future TDLib is still worth reporting: an
        // unknown-but-named channel beats silence.
        else -> type.javaClass.simpleName
            .removePrefix("AuthenticationCodeType")
            .replaceFirstChar { it.lowercase() }
            .ifBlank { null }
    }
}
