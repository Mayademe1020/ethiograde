package com.ethiograde.ui.theme

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.ethiograde.R

val EthioPrimaryLight = Color(0xFF0B6E4F)
val EthioPrimaryLightAccent = Color(0xFF1A8A65)
val EthioPrimaryContainerLight = Color(0xFFDFF5EC)
val EthioSecondaryLight = Color(0xFFF4A623)
val EthioSecondaryContainerLight = Color(0xFFFFF0D6)
val EthioErrorLight = Color(0xFFDA2A2A)
val EthioErrorContainerLight = Color(0xFFFFE8E8)
val EthioInfoLight = Color(0xFF1A6FD4)
val EthioSuccessLight = Color(0xFF18A558)
val EthioSuccessContainerLight = Color(0xFFE0F7EA)
val EthioScaffoldLight = Color(0xFFF4F7F5)
val EthioSurfaceLight = Color(0xFFFFFFFF)
val EthioSurfaceVariantLight = Color(0xFFF0F4F2)
val EthioOutlineLight = Color(0xFFDDE4E0)
val EthioOnSurfaceLight = Color(0xFF0D1C17)
val EthioOnSurfaceVariantLight = Color(0xFF4A5E56)

val EthioPrimaryDark = Color(0xFF5ED4A0)
val EthioPrimaryContainerDark = Color(0xFF004D34)
val EthioSecondaryDark = Color(0xFFFFB84D)
val EthioSecondaryContainerDark = Color(0xFF4A2D00)
val EthioErrorDark = Color(0xFFFF8A8A)
val EthioErrorContainerDark = Color(0xFF5C1515)
val EthioScaffoldDark = Color(0xFF0A1410)
val EthioSurfaceDark = Color(0xFF121F1A)
val EthioSurfaceVariantDark = Color(0xFF1C2B24)
val EthioOutlineDark = Color(0xFF2C3E35)
val EthioOnSurfaceDark = Color(0xFFE4EDE9)
val EthioOnSurfaceVariantDark = Color(0xFF8BA898)

@Immutable
data class EthioSemanticColors(
    val success: Color,
    val successContainer: Color,
    val info: Color,
    val warning: Color,
    val warningContainer: Color
)

val LocalEthioColors = staticCompositionLocalOf {
    EthioSemanticColors(
        success = EthioSuccessLight,
        successContainer = EthioSuccessContainerLight,
        info = EthioInfoLight,
        warning = EthioSecondaryLight,
        warningContainer = EthioSecondaryContainerLight
    )
}

private val LightColorScheme = lightColorScheme(
    primary = EthioPrimaryLight,
    onPrimary = Color.White,
    primaryContainer = EthioPrimaryContainerLight,
    onPrimaryContainer = Color(0xFF053827),
    secondary = EthioSecondaryLight,
    onSecondary = Color(0xFF291800),
    secondaryContainer = EthioSecondaryContainerLight,
    onSecondaryContainer = Color(0xFF4A2D00),
    tertiary = EthioInfoLight,
    onTertiary = Color.White,
    error = EthioErrorLight,
    onError = Color.White,
    errorContainer = EthioErrorContainerLight,
    onErrorContainer = Color(0xFF690005),
    background = EthioScaffoldLight,
    onBackground = EthioOnSurfaceLight,
    surface = EthioSurfaceLight,
    onSurface = EthioOnSurfaceLight,
    surfaceVariant = EthioSurfaceVariantLight,
    onSurfaceVariant = EthioOnSurfaceVariantLight,
    outline = EthioOutlineLight
)

private val DarkColorScheme = darkColorScheme(
    primary = EthioPrimaryDark,
    onPrimary = Color(0xFF003824),
    primaryContainer = EthioPrimaryContainerDark,
    onPrimaryContainer = Color(0xFFA6F5CD),
    secondary = EthioSecondaryDark,
    onSecondary = Color(0xFF3E2400),
    secondaryContainer = EthioSecondaryContainerDark,
    onSecondaryContainer = Color(0xFFFFDEAD),
    tertiary = Color(0xFF7CB7FF),
    onTertiary = Color(0xFF002E5C),
    error = EthioErrorDark,
    onError = Color(0xFF470003),
    errorContainer = EthioErrorContainerDark,
    onErrorContainer = Color(0xFFFFDAD6),
    background = EthioScaffoldDark,
    onBackground = EthioOnSurfaceDark,
    surface = EthioSurfaceDark,
    onSurface = EthioOnSurfaceDark,
    surfaceVariant = EthioSurfaceVariantDark,
    onSurfaceVariant = EthioOnSurfaceVariantDark,
    outline = EthioOutlineDark
)

val PlusJakartaSans = FontFamily(
    Font(R.font.plus_jakarta_sans_regular, FontWeight.Normal, FontStyle.Normal),
    Font(R.font.plus_jakarta_sans_bold, FontWeight.Bold, FontStyle.Normal),
    Font(R.font.plus_jakarta_sans_bold, FontWeight.SemiBold, FontStyle.Normal),
    Font(R.font.plus_jakarta_sans_italic, FontWeight.Normal, FontStyle.Italic),
    Font(R.font.plus_jakarta_sans_bold_italic, FontWeight.Bold, FontStyle.Italic)
)

val EthioTypography = Typography(
    displaySmall = TextStyle(fontFamily = PlusJakartaSans, fontWeight = FontWeight.Bold, fontSize = 32.sp, lineHeight = 38.sp),
    headlineMedium = TextStyle(fontFamily = PlusJakartaSans, fontWeight = FontWeight.Bold, fontSize = 24.sp, lineHeight = 30.sp),
    headlineSmall = TextStyle(fontFamily = PlusJakartaSans, fontWeight = FontWeight.Bold, fontSize = 20.sp, lineHeight = 26.sp),
    titleLarge = TextStyle(fontFamily = PlusJakartaSans, fontWeight = FontWeight.Bold, fontSize = 18.sp, lineHeight = 24.sp),
    titleMedium = TextStyle(fontFamily = PlusJakartaSans, fontWeight = FontWeight.SemiBold, fontSize = 16.sp, lineHeight = 22.sp),
    titleSmall = TextStyle(fontFamily = PlusJakartaSans, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, lineHeight = 20.sp),
    bodyLarge = TextStyle(fontFamily = PlusJakartaSans, fontWeight = FontWeight.Normal, fontSize = 15.sp, lineHeight = 22.sp),
    bodyMedium = TextStyle(fontFamily = PlusJakartaSans, fontWeight = FontWeight.Normal, fontSize = 14.sp, lineHeight = 20.sp),
    bodySmall = TextStyle(fontFamily = PlusJakartaSans, fontWeight = FontWeight.Normal, fontSize = 12.sp, lineHeight = 16.sp),
    labelLarge = TextStyle(fontFamily = PlusJakartaSans, fontWeight = FontWeight.SemiBold, fontSize = 14.sp, lineHeight = 18.sp),
    labelMedium = TextStyle(fontFamily = PlusJakartaSans, fontWeight = FontWeight.Medium, fontSize = 12.sp, lineHeight = 16.sp),
    labelSmall = TextStyle(fontFamily = PlusJakartaSans, fontWeight = FontWeight.Medium, fontSize = 11.sp, lineHeight = 14.sp)
)

val EthioShapes = Shapes(
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(14.dp),
    large = RoundedCornerShape(18.dp),
    extraLarge = RoundedCornerShape(24.dp)
)

@Composable
fun EthioGradeTheme(
    darkTheme: Boolean = false,
    content: @Composable () -> Unit
) {
    val colorScheme = if (darkTheme) DarkColorScheme else LightColorScheme
    val semantics = if (darkTheme) {
        EthioSemanticColors(
            success = Color(0xFF5ED4A0),
            successContainer = Color(0xFF0A3D28),
            info = Color(0xFF7CB7FF),
            warning = EthioSecondaryDark,
            warningContainer = EthioSecondaryContainerDark
        )
    } else {
        EthioSemanticColors(
            success = EthioSuccessLight,
            successContainer = EthioSuccessContainerLight,
            info = EthioInfoLight,
            warning = EthioSecondaryLight,
            warningContainer = EthioSecondaryContainerLight
        )
    }

    androidx.compose.runtime.CompositionLocalProvider(LocalEthioColors provides semantics) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = EthioTypography,
            shapes = EthioShapes,
            content = content
        )
    }
}
