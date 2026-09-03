/**
 * Builds a log message on demand using String.format(), without paying the
 * String.format() CPU cost when the entry's level is filtered out before
 * ever being buffered. Pass this instead of a pre-formatted String to
 * Logger.error()/warn()/info()/debug() when the message is expensive to build.
 *
 *   Logger.fine(new LogMessage('processed {0} of {1} records', processed, total));
 *
 * getMessage() is only called internally once Logger has already decided the
 * entry passes the configured minimum level.
 */
public class LogMessage {

    private final String unformattedMessage;
    private final List<Object> inputs;

    public LogMessage(String unformattedMessage) {
        this(unformattedMessage, new List<Object>());
    }

    public LogMessage(String unformattedMessage, Object input1) {
        this(unformattedMessage, new List<Object>{ input1 });
    }

    public LogMessage(String unformattedMessage, Object input1, Object input2) {
        this(unformattedMessage, new List<Object>{ input1, input2 });
    }

    public LogMessage(String unformattedMessage, Object input1, Object input2, Object input3) {
        this(unformattedMessage, new List<Object>{ input1, input2, input3 });
    }

    public LogMessage(String unformattedMessage, List<Object> inputs) {
        this.unformattedMessage = unformattedMessage;
        this.inputs = inputs == null ? new List<Object>() : inputs;
    }

    public String getMessage() {
        if (inputs.isEmpty()) {
            return unformattedMessage;
        }
        return String.format(unformattedMessage, inputs);
    }
}
