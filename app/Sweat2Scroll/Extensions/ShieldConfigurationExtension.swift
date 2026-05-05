// Extensions/ShieldConfigurationExtension.swift
// ⚠️  This file lives in the MAIN APP target and is intentionally empty of
//     class definitions.
//
// The actual ShieldConfigurationDataSource subclass lives exclusively in:
//   ShieldConfigurationExtension/Sweat2ScrollShieldConfiguration.swift
// It must NOT be compiled into the main app target — doing so causes
// "Method does not override any method from its superclass" compile errors
// because the superclass is only available when ManagedSettingsUI is linked
// as part of the Shield Configuration Extension target.

// No types defined here. File retained for Xcode group structure clarity.
