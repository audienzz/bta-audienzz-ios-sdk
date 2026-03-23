import Foundation

enum BtaEventType: String {
    case pageView            = "btafeed.pageview"
    case viewableImpression  = "btafeed.viewable_impression"
    case adImpression        = "btafeed.ad_impression"
    case adClick             = "btafeed.ad_click"
    case articleImpression   = "btafeed.article_impression"
    case articleClick        = "btafeed.article_click"
}
