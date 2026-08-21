package dev.telegrammcp.server.auth

import it.tdlight.jni.TdApi
import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.Test

class AuthCodeChannelTest {

    @Test
    fun `names every channel Telegram can pick`() {
        assertThat(AuthCodeChannel.of(TdApi.AuthenticationCodeTypeTelegramMessage()))
            .isEqualTo("telegramApp")
        assertThat(AuthCodeChannel.of(TdApi.AuthenticationCodeTypeSms())).isEqualTo("sms")
        assertThat(AuthCodeChannel.of(TdApi.AuthenticationCodeTypeCall())).isEqualTo("call")
        // The flash/missed-call codes are the ones a user never finds on their
        // own: nothing is delivered, the calling number *is* the code.
        assertThat(AuthCodeChannel.of(TdApi.AuthenticationCodeTypeFlashCall())).isEqualTo("flashCall")
        assertThat(AuthCodeChannel.of(TdApi.AuthenticationCodeTypeMissedCall())).isEqualTo("missedCall")
        assertThat(AuthCodeChannel.of(TdApi.AuthenticationCodeTypeFragment())).isEqualTo("fragment")
        assertThat(AuthCodeChannel.of(TdApi.AuthenticationCodeTypeFirebaseAndroid()))
            .isEqualTo("firebase")
    }

    @Test
    fun `reports an unmapped channel instead of staying silent`() {
        // Stand-in for a type a future TDLib adds: the wizard should still be
        // able to tell the user something rather than show a bare code box.
        assertThat(AuthCodeChannel.of(TdApi.AuthenticationCodeTypeSmsPhrase())).isEqualTo("smsPhrase")
        assertThat(AuthCodeChannel.of(null)).isNull()
    }

    @Test
    fun `the channel survives the trip into the wizard DTO`() {
        val dto = AuthStateDto.from(
            AuthState.WaitingCode(
                phoneNumber = "+996700123456",
                codeChannel = "missedCall",
                nextCodeChannel = "sms",
                resendTimeoutSeconds = 60,
            ),
        )

        assertThat(dto.state).isEqualTo("waitingCode")
        assertThat(dto.phoneNumber).isEqualTo("+996700123456")
        assertThat(dto.codeChannel).isEqualTo("missedCall")
        assertThat(dto.nextCodeChannel).isEqualTo("sms")
        assertThat(dto.resendTimeoutSeconds).isEqualTo(60)
    }
}
