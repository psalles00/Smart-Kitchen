import SwiftUI

/// Lightweight recipe thumbnail view that downsamples `recipe.imageData`
/// into a cached, right-sized `PlatformImage` instead of decoding the
/// full-resolution blob every body evaluation.
///
/// The actual bytes in `recipe.imageData` are never modified — this is
/// purely a render-time optimization that can be removed without any
/// data migration.
struct RecipeThumbnail<Placeholder: View>: View {
    let recipe: Recipe
    /// Target maximum pixel dimension for the downsampled image.
    /// Pick a value slightly larger than the rendered size × screen scale.
    let maxPixel: CGFloat
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: PlatformImage?
    @State private var loadedKey: String?

    private var taskKey: String {
        "\(recipe.id.uuidString)#\(recipe.updatedAt.timeIntervalSinceReferenceDate)@\(Int(maxPixel))"
    }

    private var cacheKey: String? {
        guard let data = recipe.imageData, !data.isEmpty else { return nil }
        return RecipeImageCache.key(recipeID: recipe.id, dataCount: data.count, maxPixel: maxPixel)
    }

    var body: some View {
        Group {
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder()
            }
        }
        .task(id: taskKey) {
            await loadIfNeeded()
        }
    }

    private func loadIfNeeded() async {
        guard let data = recipe.imageData, !data.isEmpty, let key = cacheKey else {
            if image != nil { image = nil }
            loadedKey = nil
            return
        }
        if loadedKey == key, image != nil { return }

        // Fast path: synchronous cache hit.
        if let hit = RecipeImageCache.shared.cachedThumbnail(key: key) {
            image = hit
            loadedKey = key
            return
        }

        let produced = await RecipeImageCache.shared.thumbnail(
            key: key,
            data: data,
            maxPixel: maxPixel
        )
        // Task may have been cancelled / replaced by now; only commit if
        // the key we worked on still matches what the view wants.
        guard cacheKey == key else { return }
        image = produced
        loadedKey = key
    }
}
