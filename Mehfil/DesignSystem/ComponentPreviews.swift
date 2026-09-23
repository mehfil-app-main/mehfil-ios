import SwiftUI

// Previews for the design system, in both appearances.
//
// There are no storyboards here, so these are the only way to review a component's states without building
// and navigating to the screen that uses it — and they are what catches a contrast regression in the dark set.

#Preview("Buttons") {
    PreviewFrame {
        MButton(title: "Primary") {}
        MButton(title: "Secondary", style: .secondary) {}
        MButton(title: "Tertiary", style: .tertiary, size: .compact) {}
        MButton(title: "Destructive", style: .destructive) {}
        MButton(title: "Disabled") {}.disabled(true)
        MButton(title: "Working", loading: true) {}
    }
}

#Preview("Buttons · dark") {
    PreviewFrame {
        MButton(title: "Primary") {}
        MButton(title: "Secondary", style: .secondary) {}
        MButton(title: "Destructive", style: .destructive) {}
    }
    .preferredColorScheme(.dark)
}

#Preview("Fields") {
    @Previewable @State var text = "Mehfil Decor"
    @Previewable @State var secret = "Secret123"
    @Previewable @State var phone = "98110"

    PreviewFrame {
        InputField(label: "Business name", text: $text)
        PasswordField(label: "Password", text: $secret)
        PhoneField(text: $phone)
        InputField(label: "With an error", text: .constant(""), error: "This one is required.")
    }
}

#Preview("Status chips") {
    PreviewFrame {
        ForEach(ChipKind.allCases, id: \.self) { StatusChip(kind: $0) }
    }
}

#Preview("Avatars") {
    PreviewFrame {
        HStack(spacing: Space.sm) {
            ForEach(["Vikram Kapoor", "Ritu Sharma", "Harpreet Gill", "Ajay", ""], id: \.self) {
                Avatar(index: nil, name: $0)
            }
        }
    }
}

#Preview("Empty state") {
    PreviewFrame {
        EmptyState(
            headline: "No events booked",
            line: "Create your first event and Mehfil starts watching the dates, the money and the crew.",
            actionTitle: "Create event",
            actionIcon: "plus",
            primary: true
        ) {}
    }
}

private struct PreviewFrame<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) { content }
            .padding(Space.lg)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(MColor.ground)
    }
}
