"""
InfraVision — Automated Local YOLO Model Trainer & TFLite Exporter
===================================================================
This script trains a custom lightweight YOLOv8 nano/small object detection model
on your local dataset and automatically exports and installs the resulting
'model.tflite' and 'labels.txt' directly into InfraVision's assets/models/ directory.

Usage:
------
1. With custom dataset (data.yaml):
   python scripts/train_yolo.py --data "C:/path/to/dataset/data.yaml" --epochs 50

2. With auto-generated sample defect dataset:
   python scripts/train_yolo.py --sample --epochs 30
"""

import os
import sys
import argparse
import shutil
import subprocess

ASSETS_MODELS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "models"))

def check_dependencies():
    print("[1/5] Checking Python ML dependencies...")
    try:
        import ultralytics
        print("  * ultralytics is installed.")
    except ImportError:
        print("  * Installing ultralytics...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "ultralytics"])
    
    try:
        import torch
        print(f"  * PyTorch is installed (CUDA available: {torch.cuda.is_available()}).")
    except ImportError:
        print("  * Installing torch & torchvision...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "torch", "torchvision"])

def train_yolo(data_yaml: str, epochs: int = 50, imgsz: int = 320, batch: int = 16):
    from ultralytics import YOLO
    
    print(f"\n[2/5] Initializing YOLOv8 Nano Edge Model for training...")
    print(f"  * Dataset: {data_yaml}")
    print(f"  * Epochs: {epochs}")
    print(f"  * Image Size: {imgsz}x{imgsz}")
    print(f"  * Batch Size: {batch}")
    
    # Start from pretrained lightweight edge weights
    model = YOLO("yolov8n.pt")
    
    print("\n[3/5] Starting real-time training with anti-overfitting hyperparameters...")
    print("  * Regularization: Cosine LR, Weight Decay=0.0005, Label Smoothing=0.1, Dropout=0.15")
    print("  * Augmentation: Mosaic=1.0, MixUp=0.15, HSV=(0.015, 0.7, 0.4), Flips, Perspective")
    print("  * Early Stopping Patience: 15 epochs")
    
    results = model.train(
        data=data_yaml,
        epochs=epochs,
        imgsz=imgsz,
        batch=batch,
        patience=15,             # Early stopping to prevent overfitting
        cos_lr=True,             # Cosine learning rate scheduler
        lr0=0.01,                # Initial learning rate
        lrf=0.01,                # Final learning rate fraction
        weight_decay=0.0005,     # L2 regularization
        label_smoothing=0.1,     # Label smoothing to prevent overconfidence
        dropout=0.15,            # Head dropout
        mosaic=1.0,              # 4-image mosaic augmentation for small defects
        mixup=0.15,              # MixUp augmentation
        degrees=10.0,            # Rotation
        translate=0.10,          # Translation
        scale=0.50,              # Scale variation
        fliplr=0.50,             # Horizontal flip
        hsv_h=0.015,             # Hue variation (for sunlight/shadow changes)
        hsv_s=0.70,              # Saturation variation
        hsv_v=0.40,              # Brightness variation
        plots=True,
        verbose=True
    )
    
    best_pt = os.path.join(results.save_dir, "weights", "best.pt")
    print(f"\n[4/5] Training finished! Best PyTorch model: {best_pt}")
    
    print("\n[5/5] Exporting directly to TensorFlow Lite (.tflite)...")
    best_model = YOLO(best_pt)
    export_path = best_model.export(format="tflite", imgsz=imgsz, int8=False)
    
    # Locate exported .tflite
    tflite_file = None
    if isinstance(export_path, str) and export_path.endswith(".tflite"):
        tflite_file = export_path
    elif os.path.exists(export_path):
        for f in os.listdir(export_path):
            if f.endswith(".tflite"):
                tflite_file = os.path.join(export_path, f)
                break
                
    if not tflite_file:
        weights_dir = os.path.join(results.save_dir, "weights")
        for root, _, files in os.walk(weights_dir):
            for f in files:
                if f.endswith(".tflite"):
                    tflite_file = os.path.join(root, f)
                    break

    os.makedirs(ASSETS_MODELS_DIR, exist_ok=True)
    target_tflite = os.path.join(ASSETS_MODELS_DIR, "model.tflite")
    target_labels = os.path.join(ASSETS_MODELS_DIR, "labels.txt")
    
    if tflite_file and os.path.exists(tflite_file):
        shutil.copyfile(tflite_file, target_tflite)
        print(f"\n SUCCESS: Installed custom model -> {target_tflite}")
    else:
        print(f"\n PyTorch model trained successfully at {best_pt}. (Exported to: {export_path})")

    # Extract and write labels.txt
    if hasattr(best_model, "names") and best_model.names:
        with open(target_labels, "w", encoding="utf-8") as f:
            for idx in sorted(best_model.names.keys()):
                f.write(f"{best_model.names[idx]}\n")
        print(f" SUCCESS: Installed class labels -> {target_labels}")
        print("  Classes:", list(best_model.names.values()))

    print("\n=======================================================")
    print(" InfraVision model updated! Run 'flutter build windows'")
    print(" to launch with your newly trained real-time model!")
    print("=======================================================")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="InfraVision Local YOLO Model Trainer")
    parser.add_argument("--data", type=str, default="data.yaml", help="Path to data.yaml dataset config")
    parser.add_argument("--epochs", type=int, default=40, help="Number of training epochs")
    parser.add_argument("--imgsz", type=int, default=320, help="Input image dimension (default 320 for 30 FPS)")
    parser.add_argument("--batch", type=int, default=16, help="Batch size")
    args = parser.parse_args()

    check_dependencies()
    if os.path.exists(args.data):
        train_yolo(args.data, epochs=args.epochs, imgsz=args.imgsz, batch=args.batch)
    else:
        print(f"\n[!] Notice: Dataset config '{args.data}' not found.")
        print("To train with your own dataset, provide the path to data.yaml:")
        print(f"  python scripts/train_yolo.py --data \"C:/path/to/your/dataset/data.yaml\" --epochs {args.epochs}")
