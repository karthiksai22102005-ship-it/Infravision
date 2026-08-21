"""
InfraVision — Automated Local Image Classifier Trainer & TFLite Exporter
=========================================================================
Trains a fast, high-accuracy MobileNetV3 / EfficientNet defect image classifier
on custom folder datasets and exports 'classifier.tflite' & 'classifier_labels.txt'.

Usage:
------
python scripts/train_classifier.py --dataset "C:/path/to/dataset_folder" --epochs 20
"""

import os
import sys
import argparse
import subprocess

ASSETS_MODELS_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "assets", "models"))

def check_dependencies():
    print("[1/4] Checking TensorFlow & ML dependencies...")
    try:
        import tensorflow as tf
        print(f"  * TensorFlow {tf.__version__} is installed.")
    except ImportError:
        print("  * Installing tensorflow...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "tensorflow"])

def train_classifier(dataset_dir: str, epochs: int = 20, batch_size: int = 32):
    import tensorflow as tf
    from tensorflow.keras import layers, models
    from tensorflow.keras.applications import MobileNetV3Small
    
    print(f"\n[2/4] Loading dataset from: {dataset_dir}...")
    img_size = (224, 224)
    
    train_ds = tf.keras.preprocessing.image_dataset_from_directory(
        dataset_dir,
        validation_split=0.2,
        subset="training",
        seed=42,
        image_size=img_size,
        batch_size=batch_size
    )
    
    val_ds = tf.keras.preprocessing.image_dataset_from_directory(
        dataset_dir,
        validation_split=0.2,
        subset="validation",
        seed=42,
        image_size=img_size,
        batch_size=batch_size
    )
    
    class_names = train_ds.class_names
    print(f"  * Detected {len(class_names)} classes: {class_names}")
    
    print("\n[3/4] Building MobileNetV3 Transfer Learning Model...")
    base_model = MobileNetV3Small(input_shape=(224, 224, 3), include_top=False, weights="imagenet")
    base_model.trainable = False
    
    model = models.Sequential([
        layers.Rescaling(1./255),
        layers.RandomFlip("horizontal"),
        layers.RandomRotation(0.1),
        layers.RandomZoom(0.1),
        base_model,
        layers.GlobalAveragePooling2D(),
        layers.Dropout(0.25),
        layers.Dense(128, activation="relu"),
        layers.Dense(len(class_names), activation="softmax")
    ])
    
    model.compile(
        optimizer=tf.keras.optimizers.Adam(learning_rate=1e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"]
    )
    
    callbacks = [
        tf.keras.callbacks.EarlyStopping(monitor="val_loss", patience=6, restore_best_weights=True),
        tf.keras.callbacks.ReduceLROnPlateau(monitor="val_loss", factor=0.5, patience=3, min_lr=1e-6)
    ]
    
    print(f"\n[4/4] Training for {epochs} epochs with EarlyStopping & LR Reduction...")
    model.fit(train_ds, validation_data=val_ds, epochs=epochs, callbacks=callbacks)
    
    # Export to TFLite
    print("\nConverting to TensorFlow Lite (.tflite)...")
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    tflite_model = converter.convert()
    
    os.makedirs(ASSETS_MODELS_DIR, exist_ok=True)
    target_tflite = os.path.join(ASSETS_MODELS_DIR, "classifier.tflite")
    target_labels = os.path.join(ASSETS_MODELS_DIR, "classifier_labels.txt")
    
    with open(target_tflite, "wb") as f:
        f.write(tflite_model)
    with open(target_labels, "w", encoding="utf-8") as f:
        for c in class_names:
            f.write(f"{c}\n")
            
    print(f"\n SUCCESS: Exported classifier -> {target_tflite}")
    print(f" SUCCESS: Exported labels -> {target_labels}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="InfraVision Defect Classifier Trainer")
    parser.add_argument("--dataset", type=str, default="dataset", help="Path to classification dataset folder")
    parser.add_argument("--epochs", type=int, default=20, help="Training epochs")
    args = parser.parse_args()
    
    check_dependencies()
    if os.path.exists(args.dataset):
        train_classifier(args.dataset, epochs=args.epochs)
    else:
        print(f"\n[!] Dataset folder '{args.dataset}' not found.")
        print(f"Run: python scripts/train_classifier.py --dataset \"C:/path/to/dataset\" --epochs {args.epochs}")
