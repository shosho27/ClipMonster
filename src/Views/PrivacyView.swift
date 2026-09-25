import SwiftUI

struct PrivacyPolicyView: View {
    var onClose: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Privacy Policy").font(.title2).bold()
                Spacer()
                Button("Done") { onClose() }
                    .keyboardShortcut(.cancelAction)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text("ClipMonster is a menu bar clipboard manager. It stores a history of items you copy so you can find and reuse them later.")
                    Text("What is stored").font(.headline)
                    Text("Text, images, and file references you copy are saved on this Mac. Screenshots are written as PNG files in ClipMonster's storage folder (Application Support, or a folder you choose). Optional OCR text from images is stored with those items. Preferences, a storage-folder bookmark, and optional file-clip bookmarks stay on this Mac as well.")
                    Text("What is not collected").font(.headline)
                    Text("ClipMonster does not create an account, does not include analytics or crash reporters, and does not send clipboard contents or any other data over the network.")
                    Text("Secrets").font(.headline)
                    Text("Items marked with the concealed, transient, or auto-generated pasteboard types, and copies made while a known password manager is frontmost, are not added to history. You can pause capture at any time and purge stored history from Preferences.")
                    Text("Permissions").font(.headline)
                    Text("Global shortcuts use system hotkeys. Auto-paste in the Direct edition needs Accessibility. The Mac App Store edition copies an item and you press ⌘V.")
                    Text("Your control").font(.headline)
                    Text("You choose whether history survives a reboot, where files are stored, whether capture is paused, and when to delete items. Purging history removes ClipMonster's index and the PNG files it created.")
                    Text("Contact").font(.headline)
                    Text("Questions about this policy: shane.shornock@gmail.com")
                }
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 360)
    }
}
