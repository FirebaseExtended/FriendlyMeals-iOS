//
// FriendlyMeals
//
// Copyright © 2025 Google LLC.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import Foundation
import Observation
import FirebaseFirestore
import FirebaseAuth

enum RecipeStoreError: Error {
  case missingRecipeID
  case likeDecodingError(String)
  case reviewDecodingError(String)
}

@Observable
class RecipeStore {
  private let db = Firestore.firestore(database: "default")

  private(set) var filterConfiguration: FilterConfiguration? = nil

  private static let recipeCollection = "recipes"

  @MainActor private(set) var topTags: [String] = []
  @MainActor private(set) var recipes = [Recipe]()

  private static func defaultFilter(_ store: Firestore) -> Pipeline {
    // TODO: Implement default filter pipeline query with likes count aggregation on-the-fly.
    return store.pipeline().collection(recipeCollection)
  }

  private var activeQuery: Pipeline {
    let filter = activeFilters ?? RecipeStore.defaultFilter
    return filter(db)
  }

  private var activeFilters: ((Firestore) -> Pipeline)?

  private func applyConfiguration(_ configuration: FilterConfiguration,
                                  to pipeline: Pipeline,
                                  using db: Firestore,
                                  currentUserID: String? = Auth.auth().currentUser?.uid) -> Pipeline {
    // TODO: Build the multi-stage query pipeline using the active FilterConfiguration.
    return pipeline
  }

  func applyConfiguration(_ configuration: FilterConfiguration) {
    filterConfiguration = configuration
    let output = { (store: Firestore) -> Pipeline in
      let pipeline = store.pipeline().collection(RecipeStore.recipeCollection)
      return self.applyConfiguration(configuration, to: pipeline, using: store)
    }
    activeFilters = output
  }

  func add(_ recipe: Recipe) async throws {
    // TODO: Add recipe to the database.
  }
  
  func fetchRecipes() async throws {
    // TODO: Retrieve saved recipe documents from the pipeline query.
    self.recipes = []
  }

  @discardableResult
  func fetchPopularTags() async throws -> [String] {
    // TODO: Fetch the top 10 most popular tags using unnest, aggregate, and sort.
    return []
  }

  func delete(_ recipe: Recipe) async throws {
    guard let id = recipe.id else {
      throw RecipeStoreError.missingRecipeID
    }
    let docRef = db.collection(RecipeStore.recipeCollection).document(id)
    try await docRef.delete()
  }

  func update(_ recipe: Recipe) async throws {
    guard let id = recipe.id else {
      throw RecipeStoreError.missingRecipeID
    }
    let docRef = db.collection(RecipeStore.recipeCollection).document(id)
    try docRef.setData(from: recipe, mergeFields: ["isFavorite"])
  }
}

// Reviews
extension RecipeStore {

  fileprivate static let reviewsSubcollection = "reviews"

  func fetchReview(userID: String, recipeID: String) async throws -> Review? {
    let compositeID = "\(recipeID)_\(userID)"
    let snapshot = try await db.pipeline().documents([
      db.collection(RecipeStore.recipeCollection).document(recipeID)
        .collection(RecipeStore.reviewsSubcollection).document(compositeID),
    ]).execute()
    guard let reviewData = snapshot.results.first?.data else {
      return nil // Review didn't exist
    }

    guard let user = reviewData["userId"] as? String,
          let recipe = reviewData["recipeId"] as? String,
          let rating = reviewData["rating"] as? Double else {
      let errorMessage = "Couldn't initialize review from data: \(reviewData)"
      throw RecipeStoreError.reviewDecodingError(errorMessage)
    }

    return Review(userID: user, recipeID: recipe, rating: rating)
  }

  func saveReview(_ review: Review) throws {
    let compositeID = review.compositeID
    try db.collection(RecipeStore.recipeCollection)
      .document(review.recipeId)
      .collection(RecipeStore.reviewsSubcollection)
      .document(compositeID)
      .setData(from: review)
  }

  func fetchRating(recipeID: String) async throws -> Double {
    // TODO: Calculate the average rating dynamically using aggregation.
    return 0
  }
}
