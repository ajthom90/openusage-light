import Foundation

/// The owner-approved defaults and the legacy baseline used when an existing user has no seed marker.
struct LayoutDefaultSet {
    let metricIDs: [String]
    let migrationBaselineMetricIDs: [String]
    let pinnedMetricIDs: [String]
}

/// Everything `LayoutStore` needs at the end of startup, plus the small set of migration writes that
/// should be made after its stored properties are initialized.
struct LayoutInitialState {
    let placed: [PlacedWidget]
    let providerOrder: [String]
    let metricOrderByProvider: [String: [String]]
    let pinnedMetricIDs: Set<String>

    let shouldPersistPlaced: Bool
    let shouldPersistPins: Bool
    let seededDefaultsToPersist: Set<String>?
}

/// Loads a layout for a fresh install or an existing user. This keeps startup/default-upgrade policy in
/// one place and leaves `LayoutStore` responsible for live actions after initialization.
@MainActor
enum LayoutBootstrap {
    static func load(
        registry: WidgetRegistry,
        persistence: LayoutPersistence,
        defaults: LayoutDefaultSet
    ) -> LayoutInitialState {
        let hasStoredLayout = persistence.hasStoredLayout
        let savedPlaced = persistence.loadPlaced()?.filter { registry.descriptor(id: $0.descriptorID) != nil }
        let startingPlaced = savedPlaced ?? defaults.metricIDs
            .filter { registry.descriptor(id: $0) != nil }
            .map { PlacedWidget(descriptorID: $0) }
        let seededResult = seedNewDefaultMetrics(
            into: startingPlaced,
            persistence: persistence,
            hasStoredLayout: hasStoredLayout,
            registry: registry,
            defaults: defaults
        )

        let providerOrder = persistence.loadProviderOrder() ?? registry.providers.map(\.id)
        let metricOrderByProvider = persistence.loadMetricOrder().map {
            LayoutOrdering.normalizedMetricOrder($0, registry: registry)
        } ?? LayoutOrdering.defaultMetricOrder(registry: registry)

        // An existing value — including an empty array from a user who unpinned everything — wins. Only
        // shown metrics keep a star: a layout saved before hiding unstarred loses the stars of its
        // hidden metrics, and the fix is saved.
        let savedPins = persistence.loadPins()
        let knownPins = Set((savedPins ?? defaults.pinnedMetricIDs).filter { registry.descriptor(id: $0) != nil })
        let placedIDs = Set(seededResult.placed.map(\.descriptorID))
        let pinnedMetricIDs = knownPins.intersection(placedIDs)

        return LayoutInitialState(
            placed: seededResult.placed,
            providerOrder: providerOrder,
            metricOrderByProvider: metricOrderByProvider,
            pinnedMetricIDs: pinnedMetricIDs,
            shouldPersistPlaced: seededResult.shouldPersistPlaced,
            shouldPersistPins: savedPins != nil && pinnedMetricIDs != knownPins,
            seededDefaultsToPersist: seededResult.shouldPersistSeededDefaults
                ? seededResult.seededDefaults
                : nil
        )
    }

    private struct SeededDefaultsResult {
        let placed: [PlacedWidget]
        let seededDefaults: Set<String>
        let shouldPersistPlaced: Bool
        let shouldPersistSeededDefaults: Bool
    }

    private static func seedNewDefaultMetrics(
        into placed: [PlacedWidget],
        persistence: LayoutPersistence,
        hasStoredLayout: Bool,
        registry: WidgetRegistry,
        defaults: LayoutDefaultSet
    ) -> SeededDefaultsResult {
        let knownDefaults = LayoutOrdering.knownMetricIDs(defaults.metricIDs, registry: registry)
        let knownDefaultSet = Set(knownDefaults)
        let hasStoredSeededDefaults = persistence.hasStoredSeededDefaults

        let seededDefaults: Set<String>
        var shouldPersistSeededDefaults = false
        if let saved = persistence.loadSeededDefaults() {
            seededDefaults = Set(LayoutOrdering.knownMetricIDs(saved, registry: registry))
            shouldPersistSeededDefaults = seededDefaults != Set(saved)
        } else if hasStoredLayout {
            seededDefaults = Set(LayoutOrdering.knownMetricIDs(defaults.migrationBaselineMetricIDs, registry: registry))
            shouldPersistSeededDefaults = true
        } else {
            seededDefaults = knownDefaultSet
            shouldPersistSeededDefaults = true
        }

        let placedIDs = Set(placed.map(\.descriptorID))
        let toAdd = knownDefaults.filter { !seededDefaults.contains($0) && !placedIDs.contains($0) }
        let nextSeededDefaults = seededDefaults.union(knownDefaultSet)
        shouldPersistSeededDefaults = shouldPersistSeededDefaults
            || !hasStoredSeededDefaults
            || nextSeededDefaults != seededDefaults

        return SeededDefaultsResult(
            placed: placed + toAdd.map { PlacedWidget(descriptorID: $0) },
            seededDefaults: nextSeededDefaults,
            shouldPersistPlaced: !toAdd.isEmpty,
            shouldPersistSeededDefaults: shouldPersistSeededDefaults
        )
    }
}

/// Pure ordering/default helpers shared by startup and live layout mutations.
enum LayoutOrdering {
    static func knownMetricIDs(_ ids: [String], registry: WidgetRegistry) -> [String] {
        var seen = Set<String>()
        return ids.filter { id in
            guard registry.descriptor(id: id) != nil, !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
    }

    static func defaultMetricOrder(registry: WidgetRegistry) -> [String: [String]] {
        var result: [String: [String]] = [:]
        for provider in registry.providers {
            result[provider.id] = registry.descriptors(for: provider.id).map(\.id)
        }
        return result
    }

    static func normalizedMetricOrder(
        _ saved: [String: [String]],
        registry: WidgetRegistry
    ) -> [String: [String]] {
        var fallback = defaultMetricOrder(registry: registry)
        for provider in registry.providers {
            let valid = registry.descriptors(for: provider.id).map(\.id)
            if let savedIDs = saved[provider.id] {
                fallback[provider.id] = normalizedMetricIDs(savedIDs, validIDs: valid)
            }
        }
        return fallback
    }

    static func normalizedMetricIDs(_ saved: [String], validIDs: [String]) -> [String] {
        let validSet = Set(validIDs)
        var seen = Set<String>()
        var ordered = saved.filter { id in
            guard validSet.contains(id), !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
        ordered.append(contentsOf: validIDs.filter { !seen.contains($0) })
        return ordered
    }
}
