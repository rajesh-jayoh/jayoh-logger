@isTest
private class LogLevelSettingSelectorTest {

    @isTest
    static void testFallsBackToDefaultRecord() {
        // Real Custom Metadata query path (mockSettings left null) —
        // running user won't match any Permission Set/Profile-named record
        // in a fresh org, so this should resolve via the shipped 'Default' record.
        Test.startTest();
        String level = LogLevelSettingSelector.getMinLevelForCurrentUser();
        Test.stopTest();

        System.assert(
            new Set<String>{'FINEST', 'DEBUG', 'INFO', 'WARN', 'ERROR'}.contains(level),
            'Expected a valid level, got: ' + level
        );
    }

    @isTest
    static void testPermissionSetOverrideTakesPrecedenceOverProfileAndDefault() {
        PermissionSet ps = new PermissionSet(Name = 'JayOh_Logger_Test_PS', Label = 'JayOh Logger Test PS');
        insert ps;
        insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = ps.Id);

        LogLevelSettingSelector.mockSettings = new List<Log_Level_Setting__mdt>{
            new Log_Level_Setting__mdt(DeveloperName = 'JayOh_Logger_Test_PS', MinimumLevel__c = 'ERROR'),
            new Log_Level_Setting__mdt(DeveloperName = 'Default', MinimumLevel__c = 'INFO')
        };

        Test.startTest();
        String level = LogLevelSettingSelector.getMinLevelForCurrentUser();
        Test.stopTest();

        System.assertEquals('ERROR', level, 'Permission Set match should win over Default');
    }

    @isTest
    static void testProfileOverrideUsedWhenNoPermissionSetMatch() {
        String profileName = [SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId()].Name.deleteWhitespace();

        LogLevelSettingSelector.mockSettings = new List<Log_Level_Setting__mdt>{
            new Log_Level_Setting__mdt(DeveloperName = profileName, MinimumLevel__c = 'WARN'),
            new Log_Level_Setting__mdt(DeveloperName = 'Default', MinimumLevel__c = 'INFO')
        };

        Test.startTest();
        String level = LogLevelSettingSelector.getMinLevelForCurrentUser();
        Test.stopTest();

        System.assertEquals('WARN', level, 'Profile match should win when no Permission Set matches');
    }

    @isTest
    static void testFallsBackToInfoWhenNoRecordsMatchAtAll() {
        LogLevelSettingSelector.mockSettings = new List<Log_Level_Setting__mdt>();

        Test.startTest();
        String level = LogLevelSettingSelector.getMinLevelForCurrentUser();
        Test.stopTest();

        System.assertEquals('INFO', level, 'Should fall back to INFO when no CMDT records exist at all');
    }

    @isTest
    static void testUnrelatedPermissionSetIsIgnored() {
        PermissionSet ps = new PermissionSet(Name = 'Unrelated_PS', Label = 'Unrelated PS');
        insert ps;
        insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = ps.Id);

        LogLevelSettingSelector.mockSettings = new List<Log_Level_Setting__mdt>{
            new Log_Level_Setting__mdt(DeveloperName = 'Some_Other_PS', MinimumLevel__c = 'ERROR'),
            new Log_Level_Setting__mdt(DeveloperName = 'Default', MinimumLevel__c = 'DEBUG')
        };

        Test.startTest();
        String level = LogLevelSettingSelector.getMinLevelForCurrentUser();
        Test.stopTest();

        System.assertEquals('DEBUG', level, 'A Permission Set with no matching CMDT record should not affect resolution');
    }
}
