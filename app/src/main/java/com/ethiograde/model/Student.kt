package com.ethiograde.model

import kotlinx.serialization.Serializable
import java.util.UUID

@Serializable
data class Student(
    val id: String = UUID.randomUUID().toString(),
    val studentId: String = "",
    val firstName: String,
    val lastName: String = "",
    val gender: String = "",
    val classIds: List<String> = emptyList(),
    val className: String = "",
    val section: String = "",
    val grade: Int = 5,
    val parentPhone: String? = null,
    val createdAtMillis: Long = System.currentTimeMillis()
) {
    val fullName: String
        get() = listOf(firstName, lastName)
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .joinToString(" ")
            .ifEmpty { studentId.ifEmpty { "Unnamed Student" } }

    val initials: String
        get() {
            val f = firstName.trim().firstOrNull()?.uppercaseChar() ?: 'S'
            val l = lastName.trim().firstOrNull()?.uppercaseChar()
            return if (l != null) "$f$l" else "$f"
        }

    fun belongsToClass(classId: String, classDisplayName: String = ""): Boolean {
        if (classIds.contains(classId)) return true
        if (classDisplayName.isNotBlank() && className.equals(classDisplayName, ignoreCase = true)) {
            return true
        }
        return false
    }
}

@Serializable
data class ClassInfo(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val grade: Int = 5,
    val section: String = "A",
    val subject: String = "Mathematics",
    val academicYear: String = "",
    val studentCount: Int = 0,
    val isHomeroom: Boolean = false,
    val createdAtMillis: Long = System.currentTimeMillis()
) {
    val displayName: String
        get() = if (name.isNotBlank()) name else "Grade $grade$section"
}

@Serializable
data class Teacher(
    val id: String = UUID.randomUUID().toString(),
    val name: String,
    val schoolName: String = "",
    val phone: String = "",
    val gradeLevels: List<Int> = emptyList(),
    val subjects: List<String> = emptyList(),
    val isActive: Boolean = false,
    val createdAtMillis: Long = System.currentTimeMillis()
)
