import PhotosUI
import SwiftUI

struct VideoImportView: View {
    @StateObject private var viewModel = VideoImportViewModel()

    var body: some View {
        Form {
            Section {
                PhotosPicker(
                    selection: $viewModel.selectedItem,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Label("Upload Lift Video", systemImage: "photo.on.rectangle.angled")
                }
                .onChange(of: viewModel.selectedItem) { _ in
                    Task { await viewModel.importSelectedVideo() }
                }

                Button {
                } label: {
                    Label("Record Video", systemImage: "camera")
                }
                .disabled(true)
            }

            if viewModel.isImporting {
                Section {
                    ProgressView("Importing video")
                }
            }

            if let importedVideo = viewModel.importedVideo {
                Section("Imported Video") {
                    MetadataRow(label: "Duration", value: "\(importedVideo.metadata.duration.clean)s")
                    MetadataRow(label: "FPS", value: importedVideo.metadata.fps.clean)
                    MetadataRow(label: "Resolution", value: importedVideo.metadata.resolution)

                    NavigationLink("Continue") {
                        LiftDetailsView(importedVideo: importedVideo)
                    }
                }
            }

            Section("Filming Guidance") {
                Label("Use a stable side-angle video.", systemImage: "iphone.gen3")
                Label("Keep full body and barbell visible.", systemImage: "figure.strengthtraining.traditional")
                Label("Avoid people crossing the frame.", systemImage: "person.crop.rectangle.badge.xmark")
                Label("Good lighting improves tracking confidence.", systemImage: "sun.max")
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Import")
    }
}

private struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}
