// AppAuthModelsTests.swift
// Pure-logic coverage for the routing enums in `AppAuthModels.swift`.
//
// These tests pin the contracts the test plan relies on:
//   - TC-ROLE-01 / TC-ROLE-02 — `PartnershipRole.canGrantOverride` and
//     `canRedeemOverride` matrix.
//   - TC-ONB-04 / TC-UI-50 — `PostAuthOnboardingStep.progressIndicator`
//     accuracy when optional steps (`prdManual`, `prdRoleSelection`) toggle.
//   - TC-ONB-05 — `previousStep` walks the visible sequence backwards
//     correctly, skipping hidden optional steps.

import XCTest
@testable import Sweat2Scroll

final class AppAuthModelsTests: XCTestCase {

    // MARK: - PartnershipRole grant/redeem matrix

    func testPartnershipRole_mutual_canGrantAndRedeem() {
        XCTAssertTrue(PartnershipRole.mutual.canGrantOverride)
        XCTAssertTrue(PartnershipRole.mutual.canRedeemOverride)
    }

    func testPartnershipRole_controller_canGrant_cannotRedeem() {
        // Per CLAUDE.md / AppAuthModels: a controller (e.g., parent) issues
        // OTPs but is not blocked themselves.
        XCTAssertTrue(PartnershipRole.controller.canGrantOverride)
        XCTAssertFalse(PartnershipRole.controller.canRedeemOverride)
    }

    func testPartnershipRole_controlled_cannotGrant_canRedeem() {
        XCTAssertFalse(PartnershipRole.controlled.canGrantOverride)
        XCTAssertTrue(PartnershipRole.controlled.canRedeemOverride)
    }

    func testPartnershipRole_displayCopyNonEmpty() {
        for role in PartnershipRole.allCases {
            XCTAssertFalse(role.displayTitle.isEmpty, "Title empty for \(role)")
            XCTAssertFalse(role.displaySubtitle.isEmpty, "Subtitle empty for \(role)")
        }
    }

    // MARK: - progressIndicator (TC-ONB-04 / TC-UI-50)

    func testProgressIndicator_minimalSequence_noManual_noRole() {
        // Visible steps: prdHealth, prdCalorie, prdApps, prdPairingPrompt → 4
        let total = 4
        for (idx, step) in [PostAuthOnboardingStep.prdHealth,
                            .prdCalorie,
                            .prdApps,
                            .prdPairingPrompt].enumerated() {
            let p = step.progressIndicator(needsManualBody: false,
                                           willShowRoleSelection: false)
            XCTAssertNotNil(p, "Step \(step) returned nil")
            XCTAssertEqual(p?.current, idx)
            XCTAssertEqual(p?.total, total)
        }
    }

    func testProgressIndicator_addsManualStepWhenNeeded() {
        // Visible: prdHealth, prdManual, prdCalorie, prdApps, prdPairingPrompt → 5
        let p = PostAuthOnboardingStep.prdManual.progressIndicator(
            needsManualBody: true, willShowRoleSelection: false)
        XCTAssertEqual(p?.current, 1)
        XCTAssertEqual(p?.total, 5)

        // prdCalorie should now be index 2
        let p2 = PostAuthOnboardingStep.prdCalorie.progressIndicator(
            needsManualBody: true, willShowRoleSelection: false)
        XCTAssertEqual(p2?.current, 2)
        XCTAssertEqual(p2?.total, 5)
    }

    func testProgressIndicator_addsRoleSelectionWhenNeeded() {
        // Visible: prdHealth, prdCalorie, prdApps, prdPairingPrompt, prdRoleSelection → 5
        let p = PostAuthOnboardingStep.prdRoleSelection.progressIndicator(
            needsManualBody: false, willShowRoleSelection: true)
        XCTAssertEqual(p?.current, 4)
        XCTAssertEqual(p?.total, 5)
    }

    func testProgressIndicator_bothOptionalsShown() {
        // Visible: prdHealth, prdManual, prdCalorie, prdApps, prdPairingPrompt,
        //          prdRoleSelection → 6
        let p = PostAuthOnboardingStep.prdRoleSelection.progressIndicator(
            needsManualBody: true, willShowRoleSelection: true)
        XCTAssertEqual(p?.current, 5)
        XCTAssertEqual(p?.total, 6)
    }

    func testProgressIndicator_returnsNilForNonPRDOrTerminalSteps() {
        // prdComplete is intentionally excluded from the strip
        XCTAssertNil(PostAuthOnboardingStep.prdComplete.progressIndicator(
            needsManualBody: false, willShowRoleSelection: false))
        // legacy & profile steps are not in the PRD chain at all
        XCTAssertNil(PostAuthOnboardingStep.modeSelection.progressIndicator(
            needsManualBody: false, willShowRoleSelection: false))
        XCTAssertNil(PostAuthOnboardingStep.soloProfile.progressIndicator(
            needsManualBody: false, willShowRoleSelection: false))
    }

    func testProgressIndicator_hiddenManualStepReturnsNilEvenIfQueried() {
        // If the branch *doesn't* need manual body but caller asks about
        // prdManual, it shouldn't be in the sequence.
        let p = PostAuthOnboardingStep.prdManual.progressIndicator(
            needsManualBody: false, willShowRoleSelection: false)
        XCTAssertNil(p)
    }

    // MARK: - previousStep walks visible sequence

    func testPreviousStep_firstStepHasNoPrevious() {
        XCTAssertNil(PostAuthOnboardingStep.prdHealth.previousStep(
            needsManualBody: false, willShowRoleSelection: false))
    }

    func testPreviousStep_skipsHiddenOptionalManualStep() {
        // Without manual body, prev of prdCalorie should be prdHealth, not prdManual.
        let prev = PostAuthOnboardingStep.prdCalorie.previousStep(
            needsManualBody: false, willShowRoleSelection: false)
        XCTAssertEqual(prev, .prdHealth)
    }

    func testPreviousStep_includesManualWhenBranchShowsIt() {
        let prev = PostAuthOnboardingStep.prdCalorie.previousStep(
            needsManualBody: true, willShowRoleSelection: false)
        XCTAssertEqual(prev, .prdManual)
    }

    func testPreviousStep_returnsNilForOutOfSequenceStep() {
        // Modes/profiles aren't part of the PRD sequence.
        let prev = PostAuthOnboardingStep.modeSelection.previousStep(
            needsManualBody: false, willShowRoleSelection: false)
        XCTAssertNil(prev)
    }
}
