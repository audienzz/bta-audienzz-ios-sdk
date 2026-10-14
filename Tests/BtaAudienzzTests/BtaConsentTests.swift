import XCTest
@testable import BtaAudienzz

/// Unit tests for the pure analytics-consent decision in `BtaConsent.analyticsDecision`.
///
/// Covers the decision table: analytics is suppressed only when GDPR positively applies
/// (`IABTCF_gdprApplies == 1`) and TCF Purpose 1 consent is not granted.
final class BtaConsentTests: XCTestCase {

    // MARK: - No CMP / GDPR not applicable → always allowed (legacy behaviour)

    func testNoCmpDataAllowsAnalytics() {
        XCTAssertTrue(BtaConsent.analyticsDecision(gdprApplies: nil, purposeConsents: nil))
    }

    func testGdprNotApplicableAllowsAnalyticsRegardlessOfPurposes() {
        XCTAssertTrue(BtaConsent.analyticsDecision(gdprApplies: 0, purposeConsents: nil))
        XCTAssertTrue(BtaConsent.analyticsDecision(gdprApplies: 0, purposeConsents: "000000000000"))
    }

    func testGdprAppliesAbsentButPurposesPresentStillAllows() {
        XCTAssertTrue(BtaConsent.analyticsDecision(gdprApplies: nil, purposeConsents: "000000000000"))
    }

    // MARK: - GDPR applies → gated on Purpose 1

    func testGdprAppliesWithPurpose1GrantedAllowsAnalytics() {
        XCTAssertTrue(BtaConsent.analyticsDecision(gdprApplies: 1, purposeConsents: "100000000000"))
    }

    func testGdprAppliesWithPurpose1GrantedAmongOthersAllowsAnalytics() {
        XCTAssertTrue(BtaConsent.analyticsDecision(gdprApplies: 1, purposeConsents: "111100001010"))
    }

    func testGdprAppliesWithPurpose1DeniedSuppressesAnalytics() {
        XCTAssertFalse(BtaConsent.analyticsDecision(gdprApplies: 1, purposeConsents: "011111111111"))
    }

    func testGdprAppliesWithAllPurposesDeniedSuppressesAnalytics() {
        XCTAssertFalse(BtaConsent.analyticsDecision(gdprApplies: 1, purposeConsents: "000000000000"))
    }

    func testGdprAppliesWithMissingPurposesStringSuppressesAnalytics() {
        XCTAssertFalse(BtaConsent.analyticsDecision(gdprApplies: 1, purposeConsents: nil))
    }

    func testGdprAppliesWithEmptyPurposesStringSuppressesAnalytics() {
        XCTAssertFalse(BtaConsent.analyticsDecision(gdprApplies: 1, purposeConsents: ""))
    }

    // MARK: - Robustness: short / malformed purposes string under GDPR

    func testSingleGrantedPurposeBitAllows() {
        XCTAssertTrue(BtaConsent.analyticsDecision(gdprApplies: 1, purposeConsents: "1"))
    }

    func testSingleDeniedPurposeBitSuppresses() {
        XCTAssertFalse(BtaConsent.analyticsDecision(gdprApplies: 1, purposeConsents: "0"))
    }
}
