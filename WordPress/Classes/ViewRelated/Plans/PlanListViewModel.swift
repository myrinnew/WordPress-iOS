import Foundation
import WordPressShared

enum PlanListViewModel {
    case Loading
    case Ready(SitePricedPlans)
    case Error(String)

    var noResultsViewModel: WPNoResultsView.Model? {
        switch self {
        case .Loading:
            return WPNoResultsView.Model(
                title: NSLocalizedString("Loading Plans...", comment: "Text displayed while loading plans details"),
                accessoryView: PlansLoadingIndicatorView()
        )
        case .Ready(_):
            return nil
        case .Error(_):
            return WPNoResultsView.Model(
                title: NSLocalizedString("Oops", comment: ""),
                message: NSLocalizedString("There was an error loading plans", comment: ""),
                buttonTitle: NSLocalizedString("Contact support", comment: "")
            )
        }
    }

    func tableFooterViewModelWithPresenter(presenter: UIViewController) -> (title: NSAttributedString, action: () -> Void)? {
        switch self {
        case .Ready:
            let action = { [weak presenter] in
                let webViewController = WPWebViewController(URL: NSURL(string: WPAutomatticTermsOfServiceURL)!)
                let navController = UINavigationController(rootViewController: webViewController)
                presenter?.presentViewController(navController, animated: true, completion: nil)
            }

            return (footerTitle, action)
        default:
            return nil
        }
    }

    private var footerTitle: NSAttributedString {
        let bodyColor = WPStyleGuide.greyDarken10().hexString()
        let linkColor = WPStyleGuide.wordPressBlue().hexString()

        let bodyStyles = "body { font-family: -apple-system; font-size: 12px; color: \(bodyColor); }"
        let linkStyles = "a { text-decoration: none; color: \(linkColor); }"

        // Non-breaking space entity prevents an orphan word if the text wraps
        let tos = NSLocalizedString("By checking out, you agree to our <a>fascinating terms and&nbsp;conditions</a>.", comment: "Terms of Service link displayed when a user is making a purchase. Text inside <a> tags will be highlighted.")
        let styledTos = "<style>" + bodyStyles + linkStyles + "</style>" + tos

        let attributedTos = try! NSMutableAttributedString(
            data: styledTos.dataUsingEncoding(NSUTF8StringEncoding)!,
            options: [NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType],
            documentAttributes: nil)

        // Apply a paragaraph style to remove extra padding at the top and bottom
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.paragraphSpacing = 0
        paragraphStyle.paragraphSpacingBefore = 0

        attributedTos.addAttribute(NSParagraphStyleAttributeName,
                                   value: paragraphStyle,
                                   range: NSMakeRange(0, attributedTos.string.characters.count - 1))

        return attributedTos
    }

    func tableViewModelWithPresenter(presenter: ImmuTablePresenter?, planService: PlanService<StoreKitStore>?) -> ImmuTable {
        switch self {
        case .Loading, .Error(_):
            return ImmuTable.Empty
        case .Ready(let siteID, let activePlan, let plans):
            let rows: [ImmuTableRow] = plans.map({ (plan, price) in
                let active = (activePlan == plan)
                let iconUrl = active ? plan.activeIconUrl : plan.iconUrl
                var action: ImmuTableAction? = nil
                if let presenter = presenter,
                    let planService = planService {
                    let sitePricedPlans = (siteID: siteID, activePlan: activePlan, availablePlans: plans)
                    action = presenter.present(self.controllerForPlanDetails(sitePricedPlans, initialPlan: plan, planService: planService))
                }

                return PlanListRow(
                    title: plan.title,
                    active: active,
                    price: price,
                    description: plan.tagline,
                    iconUrl: iconUrl,
                    action: action
                )
            })
            return ImmuTable(sections: [
                ImmuTableSection(
                    headerText: NSLocalizedString("WordPress.com Plans", comment: "Title for the Plans list header"),
                    rows: rows)
                ])
        }
    }

    func controllerForPlanDetails(sitePricedPlans: SitePricedPlans, initialPlan: Plan, planService: PlanService<StoreKitStore>) -> ImmuTableRowControllerGenerator {
        return { row in
            let planVC = PlanComparisonViewController(sitePricedPlans: sitePricedPlans, initialPlan: initialPlan, service: planService)
            let navigationVC = RotationAwareNavigationViewController(rootViewController: planVC)
            navigationVC.modalPresentationStyle = .FormSheet
            return navigationVC
        }
    }
}
