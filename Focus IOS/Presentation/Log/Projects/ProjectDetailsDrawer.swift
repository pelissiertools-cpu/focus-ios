//
//  ProjectDetailsDrawer.swift
//  Focus IOS
//

import SwiftUI

struct ProjectDetailsDrawer: View {
    let project: FocusTask
    @ObservedObject var viewModel: ProjectsViewModel
    @State private var projectTitle: String
    @State private var selectedCategoryId: UUID?
    @State private var selectedPriority: Priority
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var noteText: String
    @State private var showingDeleteConfirmation = false
    @FocusState private var isTitleFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(project: FocusTask, viewModel: ProjectsViewModel) {
        self.project = project
        self.viewModel = viewModel
        _projectTitle = State(initialValue: project.title)
        _noteText = State(initialValue: project.description ?? "")
        _selectedCategoryId = State(initialValue: project.categoryId)
        _selectedPriority = State(initialValue: project.priority)
    }

    private var hasNoteChanges: Bool {
        noteText != (project.description ?? "")
    }

    private var hasChanges: Bool {
        projectTitle != project.title || selectedCategoryId != project.categoryId || selectedPriority != project.priority || hasNoteChanges
    }

    private var currentCategoryName: String {
        if let id = selectedCategoryId,
           let cat = viewModel.categories.first(where: { $0.id == id }) {
            return cat.name
        }
        return "Category"
    }

    var body: some View {
        DrawerContainer(
            title: "Project Details",
            leadingButton: .close { dismiss() },
            trailingButton: .check(action: {
                saveTitle()
                saveNote()
                saveCategory()
                savePriority()
                dismiss()
            }, highlighted: hasChanges)
        ) {
            ScrollView {
                VStack(spacing: 12) {
                    // ─── TITLE ───
                    titleCard

                    // ─── PILL ACTIONS ───
                    actionPillsRow

                    // ─── NOTE ───
                    noteCard
                }
                .padding(.bottom, 20)
            }
            .background(.clear)
            .alert("New Category", isPresented: $showingNewCategoryAlert) {
                TextField("Category name", text: $newCategoryName)
                Button("Cancel", role: .cancel) { newCategoryName = "" }
                Button("Create") { createAndMoveToCategory() }
            } message: {
                Text("Enter a name for the new category.")
            }
            .alert("Delete project?", isPresented: $showingDeleteConfirmation) {
                Button("Delete project only") {
                    _Concurrency.Task {
                        await viewModel.deleteProjectKeepTasks(project)
                        dismiss()
                    }
                }
                Button("Delete project and tasks", role: .destructive) {
                    _Concurrency.Task {
                        await viewModel.deleteProject(project)
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("What would you like to do with the tasks inside this project?")
            }
        }
    }

    // MARK: - Title Card

    @ViewBuilder
    private var titleCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            TextField("Project title", text: $projectTitle, axis: .vertical)
                .font(.sf(.title3))
                .textFieldStyle(.plain)
                .focused($isTitleFocused)
                .onSubmit { saveTitle() }
                .padding(.horizontal, 14)
                .padding(.vertical, 16)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isTitleFocused = true
            }
        }
    }

    // MARK: - Action Pills Row

    @ViewBuilder
    private var actionPillsRow: some View {
        HStack(spacing: 8) {
            // Priority pill
            Menu {
                ForEach(Priority.allCases, id: \.self) { priority in
                    Button {
                        selectedPriority = priority
                    } label: {
                        if selectedPriority == priority {
                            Label(priority.displayName, systemImage: "checkmark")
                        } else {
                            Text(priority.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Circle()
                        .fill(selectedPriority.dotColor)
                        .frame(width: 8, height: 8)
                    Text(LocalizedStringKey(selectedPriority.displayName))
                        .font(.sf(.subheadline, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            // Category pill
            Menu {
                Button {
                    selectedCategoryId = nil
                } label: {
                    if selectedCategoryId == nil {
                        Label("None", systemImage: "checkmark")
                    } else {
                        Text("None")
                    }
                }
                ForEach(viewModel.categories) { category in
                    Button {
                        selectedCategoryId = category.id
                    } label: {
                        if selectedCategoryId == category.id {
                            Label(category.name, systemImage: "checkmark")
                        } else {
                            Text(category.name)
                        }
                    }
                }
                Divider()
                Button {
                    showingNewCategoryAlert = true
                } label: {
                    Label("New Category", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.sf(.subheadline))
                    Text(LocalizedStringKey(currentCategoryName))
                        .font(.sf(.subheadline, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassEffect(.regular.interactive(), in: .capsule)
            }

            Spacer()

            // Delete circle
            Button {
                showingDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.sf(.body, weight: .semibold))
                    .foregroundColor(.red)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
    }

    // MARK: - Note Card

    @ViewBuilder
    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Note")
                .font(.sf(.subheadline, weight: .medium))
                .foregroundColor(.primary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ZStack(alignment: .topLeading) {
                if noteText.isEmpty {
                    Text("Add a note...")
                        .font(.sf(.body))
                        .foregroundColor(.secondary.opacity(0.5))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $noteText)
                    .font(.sf(.body))
                    .frame(minHeight: 60)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 10)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16)
    }

    // MARK: - Actions

    private func saveTitle() {
        let trimmed = projectTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != project.title else { return }
        _Concurrency.Task {
            await viewModel.updateTask(project, newTitle: trimmed)
        }
    }

    private func saveNote() {
        guard hasNoteChanges else { return }
        let note = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        _Concurrency.Task {
            await viewModel.updateTaskNote(project, newNote: note.isEmpty ? nil : note)
        }
    }

    private func savePriority() {
        guard selectedPriority != project.priority else { return }
        _Concurrency.Task {
            await viewModel.updateTaskPriority(project, priority: selectedPriority)
        }
    }

    private func saveCategory() {
        guard selectedCategoryId != project.categoryId else { return }
        _Concurrency.Task {
            await viewModel.moveTaskToCategory(project, categoryId: selectedCategoryId)
        }
    }

    private func createAndMoveToCategory() {
        let name = newCategoryName
        newCategoryName = ""
        _Concurrency.Task {
            await viewModel.createCategoryAndMove(name: name, task: project)
            dismiss()
        }
    }
}
