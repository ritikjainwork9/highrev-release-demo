/**
 * Controller for the caseSummaryCard LWC. Asks the Case Summary Agent
 * (Agentforce Employee agent) for a summary of a Case through the Agent API
 * custom invocable action (generateAiAgentResponse).
 *
 * The agent call sits behind the AgentInvoker interface so tests can swap in
 * a mock and no real Agentforce call is made.
 */
public with sharing class CaseSummaryController {

    @TestVisible
    private static final String AGENT_API_NAME = 'Case_Summary_Agent';
    @TestVisible
    private static final String GENERIC_ERROR =
        'The Case Summary Agent could not generate a summary right now. Please try again later.';

    /** Abstraction over the Agentforce call so it can be mocked in tests. */
    public interface AgentInvoker {
        AgentResult invoke(String userMessage);
    }

    /** Simple, constructible result object (Invocable.Action.Result cannot be built in tests). */
    public class AgentResult {
        public Boolean isSuccess;
        public String response;
        public List<String> errors;

        public AgentResult(Boolean isSuccess, String response, List<String> errors) {
            this.isSuccess = isSuccess;
            this.response = response;
            this.errors = errors == null ? new List<String>() : errors;
        }
    }

    /** Production invoker: calls the agent through the Agent API custom invocable action. */
    public class AgentForceInvoker implements AgentInvoker {
        public AgentResult invoke(String userMessage) {
            Invocable.Action.Result result = buildAction(userMessage).invoke()[0];
            return toAgentResult(result.isSuccess(), result.getOutputParameters(), result.getErrors());
        }
    }

    /** Builds the Agent API custom action for the Case Summary Agent (no call is made here). */
    @TestVisible
    private static Invocable.Action buildAction(String userMessage) {
        Invocable.Action action = Invocable.Action.createCustomAction('generateAiAgentResponse', null, AGENT_API_NAME);
        action.setInvocationParameter('userMessage', userMessage);
        return action;
    }

    /** Converts the raw action output into an AgentResult. */
    @TestVisible
    private static AgentResult toAgentResult(Boolean isSuccess, Map<String, Object> outputs, List<Invocable.Action.Error> actionErrors) {
        List<String> errors = new List<String>();
        if (actionErrors != null) {
            for (Invocable.Action.Error err : actionErrors) {
                errors.add(err.getMessage());
            }
        }
        Object output = (isSuccess == true && outputs != null) ? outputs.get('agentResponse') : null;
        return new AgentResult(isSuccess == true, output == null ? null : extractResponseText(String.valueOf(output)), errors);
    }

    /**
     * The agent returns agentResponse as a JSON envelope such as
     * {"type":"Text","value":"Summary ..."}. Returns only the "value" text when
     * the response is a JSON object whose "value" is a string; otherwise
     * (plain text, malformed JSON, no value, or a non-text value) returns the
     * response unchanged.
     */
    @TestVisible
    private static String extractResponseText(String response) {
        if (String.isBlank(response) || !response.trim().startsWith('{')) {
            return response;
        }
        try {
            Object parsed = JSON.deserializeUntyped(response);
            if (parsed instanceof Map<String, Object>) {
                Object value = ((Map<String, Object>) parsed).get('value');
                if (value instanceof String) {
                    return (String) value;
                }
            }
        } catch (JSONException e) {
            // Not valid JSON: the agent replied in plain text, so show it as-is.
            return response;
        }
        return response;
    }

    @TestVisible
    private static AgentInvoker invoker = new AgentForceInvoker();

    /**
     * Returns the agent's summary for the given Case.
     * @param caseId Id of the Case to summarize
     * @return summary text from the Case Summary Agent
     * @throws AuraHandledException when the input is invalid, the Case is not accessible,
     *         or the agent call fails
     */
    @AuraEnabled
    public static String getSummary(Id caseId) {
        if (caseId == null || caseId.getSObjectType() != Case.SObjectType) {
            throw buildException('A valid Case Id is required to generate a summary.');
        }
        // Confirm the running user can see the Case before sending it to the agent.
        List<Case> cases = [SELECT Id FROM Case WHERE Id = :caseId WITH USER_MODE LIMIT 1];
        if (cases.isEmpty()) {
            throw buildException('The Case could not be found or you do not have access to it.');
        }

        AgentResult result;
        try {
            result = invoker.invoke('Summarize case ' + caseId);
        } catch (Exception e) {
            throw buildException(GENERIC_ERROR + ' (' + e.getMessage() + ')');
        }

        if (result == null || result.isSuccess != true) {
            throw buildException(formatErrors(result == null ? null : result.errors));
        }
        if (String.isBlank(result.response)) {
            throw buildException('The Case Summary Agent returned an empty summary. Please try again.');
        }
        return result.response;
    }

    /** Joins agent error messages into a single user-facing message. */
    @TestVisible
    private static String formatErrors(List<String> errors) {
        if (errors == null || errors.isEmpty()) {
            return GENERIC_ERROR;
        }
        return GENERIC_ERROR + ' (' + String.join(errors, '; ') + ')';
    }

    /** AuraHandledException whose message is readable both in LWC and in tests. */
    private static AuraHandledException buildException(String message) {
        AuraHandledException ex = new AuraHandledException(message);
        ex.setMessage(message);
        return ex;
    }
}