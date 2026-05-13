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

import SwiftUI

struct FilterConfiguration {

  enum SortOptions: String {
    case none = "None"
    case rating = "Rating"
    case alphabetical = "Alphabetical"
    case popularity = "Popularity"
  }

  static let sortOptions: [SortOptions] = [.none, .rating, .alphabetical, .popularity]

  var shouldShowOnlyOwnRecipes: Bool = false

  var recipeTitle = ""

  var recipeInstructions = ""

  var minimumRating: Double = 0

  var selectedTags: Set<String> = []

  var sortOption = sortOptions[0]

}

struct FilterView: View {

  @Environment(\.dismiss) private var dismiss

  init(
    tags: [String],
    configuration: FilterConfiguration? = FilterConfiguration(),
    applyFilters: @escaping (FilterConfiguration) -> ()
  ) {
    self.tags = tags
    var tagSelections = Array(repeating: false, count: tags.count)

    if let configuration = configuration {
      for i in 0 ..< tags.count {
        if configuration.selectedTags.contains(tags[i]) {
          tagSelections[i] = true
        }
      }
      self.configuration = configuration
    } else {
      self.configuration = FilterConfiguration()
    }
    self.tagSelections = tagSelections
    self.applyFilters = applyFilters
  }

  var tags: [String] {
    didSet {
      tagSelections = Array(repeating: false, count: tags.count)
    }
  }

  private let applyFilters: (FilterConfiguration) -> ()

  @State private var tagSelections: [Bool]
  @State private var configuration: FilterConfiguration

  var body: some View {
    NavigationStack {
      Form {
        Section {
          Toggle("View only my recipes", isOn: $configuration.shouldShowOnlyOwnRecipes)
        } header: {
          Label("General", systemImage: "slider.horizontal.3")
        }

        Section {
          LabeledContent("Title") {
            TextField("Scallops", text: $configuration.recipeTitle)
              .multilineTextAlignment(.trailing)
          }
          LabeledContent("Instructions") {
            TextField("Bake for 30 minutes", text: $configuration.recipeInstructions)
              .multilineTextAlignment(.trailing)
          }
        } header: {
          Label("Search", systemImage: "magnifyingglass")
        }

        Section {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Text(configuration.minimumRating.formatted())
                .font(.headline)
              Spacer()
              HStack(spacing: 2) {
                let rating = configuration.minimumRating
                ForEach(0..<5) { index in
                  let starName = index < Int(rating) ? "star.fill" : (index < Int(rating.rounded(.up)) ? "star.leadinghalf.filled" : "star")
                  Image(systemName: starName)
                    .foregroundColor(.yellow)
                }
              }
            }
            Slider(value: $configuration.minimumRating, in: 0...5, step: 0.25)
              .tint(.blue)
          }
          .padding(.vertical, 4)
        } header: {
          Label("Minimum Rating", systemImage: "star.fill")
        }

        Section {
          ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
              ForEach(0 ..< tags.count, id: \.self) { index in
                let tag = tags[index]
                let isSelected = tagSelections[index]
                Toggle(tag, isOn: $tagSelections[index])
                  .toggleStyle(.button)
                  .tint(isSelected ? .blue : .secondary)
                  .clipShape(Capsule())
              }
            }
            .padding(.vertical, 4)
          }
        } header: {
          Label("Tags", systemImage: "tag.fill")
        }

        Section {
          Picker("Sort method", selection: $configuration.sortOption) {
            ForEach(FilterConfiguration.sortOptions, id: \.self) { option in
              Text(option.rawValue).tag(option)
            }
          }
          .pickerStyle(.menu)
        } header: {
          Label("Sort By", systemImage: "arrow.up.arrow.down")
        }
      }
      .navigationTitle("Filters")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Reset") {
            configuration = FilterConfiguration()
            tagSelections = tagSelections.map { _ in false }
          }
          .foregroundColor(.red)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Apply") {
            let selectedTags = tags.indices
              .filter { tagSelections[$0] }
              .map { tags[$0] }
            configuration.selectedTags = Set(selectedTags)
            applyFilters(configuration)
            dismiss()
          }
          .fontWeight(.bold)
        }
      }
    }
  }

}
