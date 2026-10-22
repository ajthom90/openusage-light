/// A provider and its enabled widgets in the provider's metric order. Drives the grouped dashboard list.
struct ProviderGroup: Identifiable {
    let provider: Provider
    let widgets: [PlacedWidget]
    var id: String { provider.id }
}

/// A provider and a list of its metrics in the provider's custom order. Drives the Accounts detail and
/// the menu-bar pin grouping.
struct ProviderMetrics: Identifiable {
    let provider: Provider
    let metrics: [WidgetDescriptor]
    var id: String { provider.id }
}

/// Tone for the transient in-Customize pill (`LayoutStore.customizationNotice`): green success or
/// orange denial.
enum CustomizationNoticeTone {
    case positive
    case notice
}

/// The message + tone carried by the Customize pill's `TransientNotice`, so its two fields clear together.
struct CustomizationNoticeContent {
    var message: String
    var tone: CustomizationNoticeTone
}
