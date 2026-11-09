/**
 * Tests for CaseSummaryController. The agent call is always mocked, so no
 * real Agentforce call is made.
 */
@isTest
private class CaseSummaryControllerTest {

    /** Configurable mock for the agent call. */
    private class MockInvoker implements CaseSummaryController.AgentInvoker {
        private CaseSummaryController.AgentResult result;
        private Boolean throwError = false;
        public String lastMessage;

        MockInvoker(CaseSummaryController.AgentResult result) {
            this.result = result;
        }
        MockInvoker(Boolean throwError) {
            this.throwError = throwError;
        }
        public CaseSummaryController.AgentResult invoke(String userMessage) {
            lastMessage = userMessage;
            if (throwError) {
                throw new CalloutException('Agent unavailable');
            }
            return result;
        }
    }

    @testSetup
    static void setupData() {
        insert new Case(Subject = 'Printer not working', Status = 'New', Origin = 'Phone');
    }

    private static Id getCaseId() {
        return [SELECT Id FROM Case LIMIT 1].Id;
    }

    private static String callExpectingError(Id caseId) {
        try {
            CaseSummaryController.getSummary(caseId);
            Assert.fail('An AuraHandledException was expected');
        } catch (AuraHandledException e) {
            return e.getMessage();
        }
        return null;
    }

    @isTest
    static void testSuccessReturnsAgentResponse() {
        Id caseId = getCaseId();
        MockInvoker mock = new MockInvoker(
            new CaseSummaryController.AgentResult(true, 'Customer reports a printer fault.', null));
        CaseSummaryController.invoker = mock;

        Test.startTest();
        String summary = CaseSummaryController.getSummary(caseId);
        Test.stopTest();

        Assert.areEqual('Customer reports a printer fault.', summary, 'Summary should be the agent response');
        Assert.areEqual('Summarize case ' + caseId, mock.lastMessage, 'User message should reference the Case Id');
    }

    @isTest
    static void testAgentFailureThrowsWithErrors() {
        CaseSummaryController.invoker = new MockInvoker(
            new CaseSummaryController.AgentResult(false, null, new List<String>{ 'Agent is not active' }));

        Test.startTest();
        String message = callExpectingError(getCaseId());
        Test.stopTest();

        Assert.isTrue(message.contains('Agent is not active'), 'Agent error should be surfaced: ' + message);
        Assert.isTrue(message.startsWith(CaseSummaryController.GENERIC_ERROR), 'Friendly prefix expected');
    }

    @isTest
    static void testNullResultThrowsGenericError() {
        CaseSummaryController.invoker = new MockInvoker((CaseSummaryController.AgentResult) null);

        Test.startTest();
        String message = callExpectingError(getCaseId());
        Test.stopTest();

        Assert.areEqual(CaseSummaryController.GENERIC_ERROR, message, 'Generic error expected for null result');
    }

    @isTest
    static void testBlankResponseThrows() {
        CaseSummaryController.invoker = new MockInvoker(
            new CaseSummaryController.AgentResult(true, '  ', null));

        Test.startTest();
        String message = callExpectingError(getCaseId());
        Test.stopTest();

        Assert.isTrue(message.contains('empty summary'), 'Empty summary error expected: ' + message);
    }

    @isTest
    static void testInvokerExceptionIsWrapped() {
        CaseSummaryController.invoker = new MockInvoker(true);

        Test.startTest();
        String message = callExpectingError(getCaseId());
        Test.stopTest();

        Assert.isTrue(message.contains('Agent unavailable'), 'Underlying error should be included: ' + message);
    }

    @isTest
    static void testNullIdThrows() {
        MockInvoker mock = new MockInvoker(new CaseSummaryController.AgentResult(true, 'x', null));
        CaseSummaryController.invoker = mock;

        Test.startTest();
        String message = callExpectingError(null);
        Test.stopTest();

        Assert.isTrue(message.contains('valid Case Id'), 'Validation error expected: ' + message);
        Assert.isNull(mock.lastMessage, 'Agent must not be called for invalid input');
    }

    @isTest
    static void testNonCaseIdThrows() {
        Account acc = new Account(Name = 'Summary Test Account');
        insert acc;
        CaseSummaryController.invoker = new MockInvoker(new CaseSummaryController.AgentResult(true, 'x', null));

        Test.startTest();
        String message = callExpectingError(acc.Id);
        Test.stopTest();

        Assert.isTrue(message.contains('valid Case Id'), 'Validation error expected: ' + message);
    }

    @isTest
    static void testDeletedCaseThrows() {
        Case c = [SELECT Id FROM Case LIMIT 1];
        delete c;
        CaseSummaryController.invoker = new MockInvoker(new CaseSummaryController.AgentResult(true, 'x', null));

        Test.startTest();
        String message = callExpectingError(c.Id);
        Test.stopTest();

        Assert.isTrue(message.contains('could not be found'), 'Not found error expected: ' + message);
    }

    @isTest
    static void testBuildActionTargetsCaseSummaryAgent() {
        Test.startTest();
        Invocable.Action action = CaseSummaryController.buildAction('Summarize case X');
        Test.stopTest();

        Assert.areEqual('generateAiAgentResponse', action.getType(), 'Action type should be the Agent API action');
        Assert.areEqual(CaseSummaryController.AGENT_API_NAME, action.getName(), 'Action should target the Case Summary Agent');
    }

    @isTest
    static void testToAgentResultMapsOutputs() {
        Test.startTest();
        CaseSummaryController.AgentResult ok = CaseSummaryController.toAgentResult(
            true, new Map<String, Object>{ 'agentResponse' => 'Summary text' }, new List<Invocable.Action.Error>());
        CaseSummaryController.AgentResult failed = CaseSummaryController.toAgentResult(
            false, new Map<String, Object>{ 'agentResponse' => 'ignored' }, null);
        Test.stopTest();

        Assert.isTrue(ok.isSuccess, 'Success flag should be mapped');
        Assert.areEqual('Summary text', ok.response, 'agentResponse should be mapped');
        Assert.isFalse(failed.isSuccess, 'Failure flag should be mapped');
        Assert.isNull(failed.response, 'Response should be ignored on failure');
        Assert.isTrue(failed.errors.isEmpty(), 'Null errors should map to an empty list');
    }

    @isTest
    static void testFormatErrorsJoinsMessages() {
        Test.startTest();
        String joined = CaseSummaryController.formatErrors(new List<String>{ 'A', 'B' });
        String empty = CaseSummaryController.formatErrors(new List<String>());
        Test.stopTest();

        Assert.isTrue(joined.endsWith('(A; B)'), 'Errors should be joined: ' + joined);
        Assert.areEqual(CaseSummaryController.GENERIC_ERROR, empty, 'Empty list should yield generic error');
    }

    /** Maps an agentResponse string through toAgentResult as a successful action output. */
    private static String mapResponse(String agentResponse) {
        return CaseSummaryController.toAgentResult(
            true, new Map<String, Object>{ 'agentResponse' => agentResponse }, null).response;
    }

    @isTest
    static void testToAgentResultExtractsJsonValue() {
        Test.startTest();
        String text = mapResponse('{"type":"Text","value":"Summary line one\\nSummary line two"}');
        Test.stopTest();

        Assert.areEqual('Summary line one\nSummary line two', text, 'Only the JSON value text should be returned');
    }

    @isTest
    static void testToAgentResultKeepsPlainText() {
        String plain = 'Customer reports a printer fault. {not json}';

        Test.startTest();
        String text = mapResponse(plain);
        String malformed = mapResponse('{"type":"Text","value":');
        Test.stopTest();

        Assert.areEqual(plain, text, 'Plain text response should be returned unchanged');
        Assert.areEqual('{"type":"Text","value":', malformed, 'Malformed JSON should be returned unchanged');
    }

    @isTest
    static void testToAgentResultKeepsJsonWithoutValue() {
        String noValue = '{"type":"Text","message":"Summary"}';
        String jsonArray = '[{"value":"Summary"}]';

        Test.startTest();
        String text = mapResponse(noValue);
        String arrayText = mapResponse(jsonArray);
        Test.stopTest();

        Assert.areEqual(noValue, text, 'JSON without a value should be returned unchanged');
        Assert.areEqual(jsonArray, arrayText, 'A JSON array is not an envelope and should be returned unchanged');
    }

    @isTest
    static void testToAgentResultKeepsNonTextValue() {
        String numberValue = '{"type":"Number","value":42}';
        String objectValue = '{"type":"Object","value":{"text":"Summary"}}';
        String nullValue = '{"type":"Text","value":null}';

        Test.startTest();
        String numberText = mapResponse(numberValue);
        String objectText = mapResponse(objectValue);
        String nullText = mapResponse(nullValue);
        Test.stopTest();

        Assert.areEqual(numberValue, numberText, 'Numeric value should leave the response unchanged');
        Assert.areEqual(objectValue, objectText, 'Object value should leave the response unchanged');
        Assert.areEqual(nullValue, nullText, 'Null value should leave the response unchanged');
    }

    @isTest
    static void testJsonResponseReturnsValueFromGetSummary() {
        CaseSummaryController.invoker = new MockInvoker(new CaseSummaryController.AgentResult(
            true, mapResponse('{"type":"Text","value":"Printer fault reported by phone."}'), null));

        Test.startTest();
        String summary = CaseSummaryController.getSummary(getCaseId());
        Test.stopTest();

        Assert.areEqual('Printer fault reported by phone.', summary, 'getSummary should return only the value text');
    }

    @isTest
    static void testBlankJsonValueThrowsEmptySummary() {
        String blankValue = mapResponse('{"type":"Text","value":"  "}');
        CaseSummaryController.invoker = new MockInvoker(
            new CaseSummaryController.AgentResult(true, blankValue, null));

        Test.startTest();
        String message = callExpectingError(getCaseId());
        Test.stopTest();

        Assert.areEqual('  ', blankValue, 'Blank value text should be extracted as-is');
        Assert.isTrue(message.contains('empty summary'), 'Empty summary error expected: ' + message);
    }
}