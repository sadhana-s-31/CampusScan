"""
Script to generate sample student CSV, Excel, and photos for CampusScan.
"""
import os
import pandas as pd
from PIL import Image, ImageDraw, ImageFont

def generate_sample_images():
    students = [
        ('23CS001', 'Aarav Sharma', (37, 99, 235)),    # Blue
        ('23CS002', 'Diya Patel', (219, 39, 119)),    # Pink
        ('23CS003', 'Rohan Verma', (5, 150, 105)),    # Green
        ('23CS004', 'Sneha Reddy', (124, 58, 237)),   # Purple
        ('23CS005', 'Vikram Singh', (217, 119, 6))    # Amber
    ]
    
    os.makedirs('data/students', exist_ok=True)
    os.makedirs('sample_data/photos', exist_ok=True)
    
    for sid, name, color in students:
        # Create 240x240 image
        img = Image.new('RGB', (240, 240), color=color)
        draw = ImageDraw.Draw(img)
        
        # Circle avatar background
        draw.ellipse([30, 20, 210, 200], fill=(255, 255, 255, 40), outline=(255, 255, 255), width=3)
        
        # Initials
        initials = "".join([p[0] for p in name.split()[:2]]).upper()
        # Draw text (default font)
        draw.text((120, 95), initials, fill=(255, 255, 255), anchor="mm")
        
        # Bottom tag for Student ID
        draw.rectangle([20, 185, 220, 225], fill=(15, 23, 42))
        draw.text((120, 205), sid, fill=(255, 255, 255), anchor="mm")
        
        # Save as both JPG and PNG
        jpg_path = os.path.join('data/students', f"{sid}.jpg")
        img.save(jpg_path, 'JPEG', quality=95)
        
        sample_jpg = os.path.join('sample_data/photos', f"{sid}.jpg")
        img.save(sample_jpg, 'JPEG', quality=95)

def generate_sample_files():
    data = [
        {"student_id": "23CS001", "name": "Aarav Sharma"},
        {"student_id": "23CS002", "name": "Diya Patel"},
        {"student_id": "23CS003", "name": "Rohan Verma"},
        {"student_id": "23CS004", "name": "Sneha Reddy"},
        {"student_id": "23CS005", "name": "Vikram Singh"},
        {"student_id": "23CS006", "name": "Ananya Joshi"},
        {"student_id": "23CS007", "name": "Karthik Nair"},
        {"student_id": "23CS008", "name": "Meera Iyer"},
        {"student_id": "23CS009", "name": "Devendra Rao"},
        {"student_id": "23CS010", "name": "Pooja Hegde"},
    ]
    
    os.makedirs('sample_data', exist_ok=True)
    
    df = pd.DataFrame(data)
    csv_path = 'sample_data/sample_students.csv'
    xlsx_path = 'sample_data/sample_students.xlsx'
    
    df.to_csv(csv_path, index=False)
    df.to_excel(xlsx_path, index=False)
    print(f"Created {csv_path} and {xlsx_path}")

if __name__ == '__main__':
    generate_sample_images()
    generate_sample_files()
    print("Sample generation complete!")
