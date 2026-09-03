/**
 * Ordered log levels. Higher ordinal = more severe.
 * Kept as a class (not a native enum) so ordinal comparisons and
 * string parsing from Custom Metadata are straightforward.
 */
public class LogLevel {
    public static final Integer FINEST_ORD = 0;
    public static final Integer DEBUG_ORD  = 1;
    public static final Integer INFO_ORD   = 2;
    public static final Integer WARN_ORD   = 3;
    public static final Integer ERROR_ORD  = 4;

    public static Integer ordinalOf(String levelName) {
        if (String.isBlank(levelName)) {
            return INFO_ORD;
        }
        switch on levelName.toUpperCase() {
            when 'FINEST' { return FINEST_ORD; }
            when 'DEBUG'  { return DEBUG_ORD; }
            when 'INFO'   { return INFO_ORD; }
            when 'WARN'   { return WARN_ORD; }
            when 'ERROR'  { return ERROR_ORD; }
            when else     { return INFO_ORD; }
        }
    }
}
