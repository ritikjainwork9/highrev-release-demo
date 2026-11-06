import { LightningElement, api } from 'lwc';
import getSummary from '@salesforce/apex/CaseSummaryController.getSummary';

const FRIENDLY_ERROR = 'Sorry, we could not generate a summary for this case right now. Please try again in a moment.';

export default class CaseSummaryCard extends LightningElement {
    @api recordId;

    summary;
    errorMessage;
    isLoading = false;

    async handleSummarize() {
        this.isLoading = true;
        this.errorMessage = undefined;
        this.summary = undefined;
        try {
            this.summary = await getSummary({ caseId: this.recordId });
        } catch (error) {
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    reduceError(error) {
        const message = error?.body?.message;
        return message ? message : FRIENDLY_ERROR;
    }
}