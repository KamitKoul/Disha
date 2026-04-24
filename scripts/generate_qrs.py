import qrcode
import json
import os

# Campus nodes to generate QR codes for
anchors = [
    {"id": "node_mca_lab", "label": "MCA Lab Entrance"},
    {"id": "node_hallway_1", "label": "Main Hallway"},
    {"id": "node_server_room", "label": "Server Room"},
    {"id": "node_mca_office", "label": "MCA HOD Office"},
]

def generate_qrs():
    # Create output directory
    output_dir = "assets/qr_anchors"
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    print(f"Generating QR codes in {output_dir}...")

    for anchor in anchors:
        # Define the payload as per the Flutter app's requirement
        payload = json.dumps({"id": anchor["id"]})
        
        # Create QR code instance
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=10,
            border=4,
        )
        qr.add_data(payload)
        qr.make(fit=True)

        # Create and save image
        img = qr.make_image(fill_color="black", back_color="white")
        filename = f"{anchor['id']}.png"
        path = os.path.join(output_dir, filename)
        img.save(path)
        
        print(f"✅ Generated: {filename} (Data: {payload})")

if __name__ == "__main__":
    try:
        generate_qrs()
        print("\nAll anchors generated successfully! You can now print these for your campus deployment.")
    except ImportError:
        print("❌ Error: 'qrcode' library not found.")
        print("Please install it using: pip install qrcode[pil]")
