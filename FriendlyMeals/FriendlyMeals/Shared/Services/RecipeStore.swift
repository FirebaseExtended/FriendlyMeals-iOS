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
    return store.pipeline().collection(recipeCollection)
      .define([Field("__name__").documentId().as("parentRecipeId")])
      .addFields([
        store.pipeline()
          .collection("likes")
          .where(Field("recipeId").equal(Variable("parentRecipeId")))
          .aggregate([CountAll().as("count")])
          .toScalarExpression()
          .as("likes")
      ])
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
    var filters = pipeline

    if !configuration.recipeInstructions.isEmpty {
      // Search must be the first stage in a pipeline, so don't add any
      // stages before this.
      filters = filters.search(
        query: "\(configuration.recipeInstructions)",
        addFields: [
          Score().as("searchScore")
        ]
      )
    }

    if let id = currentUserID, configuration.shouldShowOnlyOwnRecipes {
      filters = filters.where(Field("authorId").equal(id))
    }

    if !configuration.recipeTitle.isEmpty {
      filters = filters.where(Field("title").like("%\(configuration.recipeTitle)%"))
    }

    if !configuration.selectedTags.isEmpty {
      filters = filters.where(Field("tags").arrayContainsAny(Array(configuration.selectedTags)))
    }

    if configuration.minimumRating > 0 {
      filters = filters
        .addFields([
          Subcollection(RecipeStore.reviewsSubcollection)
            .aggregate([Field("rating").average().as("averageRating")])
            .toScalarExpression()
            .as("averageRating")
        ])
        .where(Field("averageRating").exists() && Field("averageRating").greaterThanOrEqual(configuration.minimumRating)
      )
    }

    switch configuration.sortOption {
    case .alphabetical:
      filters = filters.sort([Field("title").ascending()])
    case .rating:
      filters = filters.sort([Field("averageRating").descending()])
    case .popularity:
      filters = filters.define([Field("__name__").documentId().as("parentRecipeId")])
        .addFields([
          db.pipeline()
            .collection("likes")
            .where(Field("recipeId").equal(Variable("parentRecipeId")))
            .aggregate([CountAll().as("count")])
            .toScalarExpression()
            .as("likes")
        ]).sort([Field("likes").descending()])
    case .none:
      // If no existing filter, sort by search score if it exists.
      if !configuration.recipeInstructions.isEmpty {
        filters = filters.sort([Field("searchScore").descending()])
      }
      break
    @unknown default:
      break
    }

    return filters
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
    let collection = db.collection(RecipeStore.recipeCollection)
    try collection.addDocument(from: recipe)
  }
  
  func fetchRecipes() async throws {
    let query = activeQuery

    let snapshot = try await query.execute()
    print(snapshot.results)
    print(self.recipes)
    self.recipes = try snapshot.results.compactMap { result in
      return try Recipe(from: result)
    }
  }

  @discardableResult
  func fetchPopularTags() async throws -> [String] {
    let snapshot = try await db.pipeline()
      .collection(RecipeStore.recipeCollection)
      .select([Field("tags")])
      .unnest(Field("tags").as("tagName"))
      .aggregate(
        [
          CountAll().as("tagCount")
        ], groups: [Field("tagName")]
      )
      .sort([Field("tagCount").descending()])
      .limit(10)
      .execute()

    let results = snapshot.results.compactMap { result in
      return result.data["tagName"] as? String
    }
    topTags = results
    return results
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
    let collectionPath = "\(RecipeStore.recipeCollection)/\(recipeID)/\(RecipeStore.reviewsSubcollection)"
    let snapshot = try await db.pipeline()
      .collection(collectionPath)
      .aggregate([
        Field("rating").average().as("averageRating")
      ]).execute()
    guard let rating = snapshot.results.first?.data["averageRating"] as? Double else {
      print("warning: unable to find rating in \(snapshot.results)")
      return 0
    }
    return rating
  }
}
