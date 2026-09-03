/**
 * Resolves the minimum log level for the current user by checking, in order:
 *   1. A Log_Level_Setting__mdt record whose DeveloperName matches an assigned Permission Set
 *   2. A record matching the user's Profile
 *   3. A record named 'Default'
 *   4. Falls back to 'INFO' if nothing is configured
 *
 * This lets you run DEBUG in a sandbox and ERROR-only in production without a deploy —
 * just add/edit Custom Metadata records per org.
 *
 * Testability note: Custom Metadata records can't be inserted via DML in Apex,
 * so a real Permission-Set/Profile-specific override can't be created inline in
 * a test. `mockSettings` lets a test inject an in-memory list of
 * Log_Level_Setting__mdt (just constructed, never inserted) to exercise the
 * precedence logic deterministically. When null (the default), the real
 * Custom Metadata is queried as normal.
 */
public without sharing class LogLevelSettingSelector {

    @TestVisible
    private static List<Log_Level_Setting__mdt> mockSettings = null;

    public static String getMinLevelForCurrentUser() {
        List<Log_Level_Setting__mdt> allSettings = getAllSettings();
        Set<String> permSetNames = permissionSetNamesForCurrentUser();
        String profileName = currentProfileName();

        Log_Level_Setting__mdt profileMatch = null;
        Log_Level_Setting__mdt defaultMatch = null;

        for (Log_Level_Setting__mdt setting : allSettings) {
            if (permSetNames.contains(setting.DeveloperName)) {
                return setting.MinimumLevel__c; // highest precedence — return immediately
            }
            if (profileMatch == null && setting.DeveloperName == profileName) {
                profileMatch = setting;
            }
            if (defaultMatch == null && setting.DeveloperName == 'Default') {
                defaultMatch = setting;
            }
        }

        if (profileMatch != null) {
            return profileMatch.MinimumLevel__c;
        }
        if (defaultMatch != null) {
            return defaultMatch.MinimumLevel__c;
        }
        return 'INFO';
    }

    private static List<Log_Level_Setting__mdt> getAllSettings() {
        if (mockSettings != null) {
            return mockSettings;
        }
        return [SELECT DeveloperName, MinimumLevel__c FROM Log_Level_Setting__mdt];
    }

    private static String currentProfileName() {
        return [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId()].Name.deleteWhitespace();
    }

    private static Set<String> permissionSetNamesForCurrentUser() {
        Set<String> names = new Set<String>();
        for (PermissionSetAssignment psa : [
            SELECT PermissionSet.Name
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
        ]) {
            names.add(psa.PermissionSet.Name);
        }
        return names;
    }
}
