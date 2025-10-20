Product Requirements Document: Image Pixelation Feature for Phoenix LiveView
1. Overview
1.1 Purpose
The Image Pixelation Feature enables users to upload an image (JPG or PNG) via a Phoenix LiveView application, which is then processed to create a pixelated effect by reducing the image to a user-configurable grid of colored squares (e.g., 32x32, 64x64, or larger). The pixelated image is rendered on an HTML canvas as a grid of colored squares, providing a visually engaging representation of the original image. The feature supports experimentation with various grid sizes to test performance and visual effects.
1.2 Scope
This feature will be integrated into an existing Phoenix LiveView application. It includes:

A user interface for uploading images and selecting grid size (e.g., 32x32, 64x64, 128x128).
Server-side image processing to generate pixelated data for configurable grid sizes.
Client-side rendering of the pixelated image on a canvas.
Basic error handling for invalid uploads or processing failures.
Performance optimizations to handle larger grid sizes efficiently.

1.3 Goals

Allow users to customize the pixelation grid size for flexibility and experimentation.
Ensure fast processing and rendering, even for large grid sizes (e.g., 64x64, 128x128).
Maintain compatibility with common image formats (JPG, PNG).
Support easy integration into the existing Phoenix application.
Enable testing of performance limits with larger grid sizes.

2. User Stories

As a user, I want to upload a JPG or PNG image and specify the grid size (e.g., 32x32, 64x64, 128x128) so that I can control the level of pixelation.
As a user, I want the pixelated image to be displayed quickly on a canvas so that I can view the result without delay, even for larger grids.
As a user, I want to receive clear error messages if the upload or processing fails so that I can understand and correct the issue.
As a user, I want to experiment with large grid sizes (e.g., 128x128 or larger) to test the visual effect and performance.
As a developer, I want the feature to be modular and reusable so that it can be easily integrated into other parts of the application.

3. Functional Requirements
3.1 Image Upload

FR1: The application must provide a form for users to upload a single image file.
Supported formats: JPG, JPEG, PNG.
Maximum file size: 10MB.


FR2: The upload form must validate file type and size before processing.
FR3: The upload must use Phoenix LiveView’s file upload capabilities to handle uploads efficiently.

3.2 Grid Size Selection

FR4: The form must include an input field (e.g., dropdown or text input) for users to select the grid size (e.g., 32x32, 64x64, 128x128).
Default: 64x64.
Supported options: 16x16, 32x32, 64x64, 128x128, with extensibility for larger sizes (e.g., 256x256).
Validate input to ensure it’s a positive integer and within a reasonable range (e.g., 4 to 256).


FR5: The selected grid size must be sent to the server with the image upload.

3.3 Image Processing

FR6: The server must process the uploaded image to create a pixelated effect by resizing it to the user-specified grid size (e.g., 64x64).
The resized image will represent each pixel as a larger square in the final output.


FR7: The server must extract the RGB color values for each pixel in the resized image.
FR8: The server must convert RGB values to hex color codes (e.g., #FF0000) for client-side rendering.
FR9: The server must return a list of pixel data in the format [{x, y, hex_color}, ...], where x and y are the coordinates of each pixel, and hex_color is the color in hex format.
FR10: The server must also return the dimensions (width and height) of the resized image.

3.4 Canvas Rendering

FR11: The client must render the pixel data on an HTML <canvas> element as a grid of colored squares.
Canvas size: 512x512 pixels (configurable).
Each pixel from the grid is rendered as a square, with size calculated to fit the canvas (e.g., 8x8 pixels per square for a 64x64 grid on a 512x512 canvas).


FR12: The client must clear the canvas before rendering a new image.
FR13: The client must use LiveView’s push_event to receive pixel data and trigger rendering.

3.5 Error Handling

FR14: Display a user-friendly error message if no file is uploaded.
FR15: Display a user-friendly error message if the uploaded file is invalid (e.g., wrong format, exceeds size limit, or processing fails).
FR16: Display an error if the selected grid size is invalid (e.g., negative, zero, or excessively large, such as >1024).

4. Non-Functional Requirements
4.1 Performance

NFR1: Image processing must complete within 2 seconds for a 10MB image with a 64x64 grid on a standard server (e.g., 2 CPU cores, 4GB RAM).
NFR2: Image processing for a 128x128 grid should complete within 5 seconds for a 10MB image.
NFR3: Canvas rendering must complete within 100ms for a 64x64 grid and 500ms for a 128x128 grid on modern browsers (e.g., Chrome, Firefox).
NFR4: The feature must handle up to 100 concurrent uploads without significant performance degradation.
NFR5: For larger grids (e.g., 256x256), provide a warning to users about potential performance impacts and suggest smaller grid sizes if processing exceeds 10 seconds.

4.2 Security

NFR6: Validate file types and sizes on both client and server to prevent malicious uploads.
NFR7: Use temporary files for uploads and ensure they are securely deleted after processing.
NFR8: Restrict uploads to JPG and PNG formats to avoid unsupported or unsafe file types.
NFR9: Validate grid size input to prevent excessive resource consumption (e.g., cap at 256x256).

4.3 Compatibility

NFR10: The feature must work on modern browsers (Chrome, Firefox, Safari, Edge) with HTML5 canvas support.
NFR11: The server-side processing must rely on ImageMagick, which must be installed on the host system.

4.4 Maintainability

NFR12: The code must be modular, with clear separation of concerns (LiveView module, template, and JavaScript).
NFR13: Include documentation for configuration options (e.g., grid size, canvas size).

5. Implementation Details
5.1 Tech Stack

Backend: Elixir with Phoenix LiveView (~> 0.20.0).
Image Processing: Mogrify (> 0.9.4) and Image (> 0.32) libraries, with ImageMagick as a system dependency.
Frontend: HTML <canvas> with JavaScript for rendering, integrated with LiveView’s event system.
Dependencies:
Elixir dependencies: {:mogrify, "~> 0.9.4"}, {:image, "~> 0.32"}.
System dependency: ImageMagick (install via brew install imagemagick on macOS or apt-get install imagemagick on Ubuntu).



5.2 File Structure

lib/my_app_web/live/image_pixelator.ex: LiveView module to handle uploads, grid size input, and processing.
lib/my_app_web/live/image_pixelator.html.leex: Template with upload form, grid size input, and canvas.
lib/my_app_web/router.ex: Update to include /pixelator route.
mix.exs: Update to include Mogrify and Image dependencies.
config/config.exs: Configure file uploads.

5.3 Processing Flow

User selects a grid size (e.g., 64x64) and uploads an image via the LiveView form.
The server validates the file and grid size, then uses Mogrify to:
Resize the image to the specified grid size (e.g., 64x64).
Extract RGB colors for each pixel.
Convert RGB to hex color codes.


The server sends pixel data [{x, y, hex_color}, ...] and dimensions {width, height} to the client via push_event.
The client JavaScript receives the data, calculates square sizes based on the canvas size and grid dimensions, and draws colored squares on the canvas.

5.4 Configuration Options

Grid Size: Configurable via form input (default: 64x64; options: 16x16, 32x32, 64x64, 128x128, up to 256x256).
Canvas Size: Default 512x512 pixels; adjustable in the template.
Max File Size: Default 10MB; configurable in config.exs.
Grid Size Limit: Cap at 256x256 to prevent excessive resource usage, with validation and error messaging.

5.5 Performance Considerations

For larger grids (e.g., 128x128 or 256x256), processing time increases quadratically (e.g., 256x256 = 65,536 pixels vs. 64x64 = 4,096 pixels).
Optimize by:
Using efficient image resizing algorithms in Mogrify.
Caching resized images temporarily if the same grid size is reused.
Implementing a progress indicator for larger grids (>128x128).


Monitor server memory and CPU usage during testing with large grids.

6. Acceptance Criteria

Image Upload and Grid Selection:
Users can upload JPG or PNG files up to 10MB.
Users can select a grid size (e.g., 16x16, 32x32, 64x64, 128x128) via a form input.
Invalid files or grid sizes display appropriate error messages.


Pixelation:
The uploaded image is resized to the specified grid size, with each pixel’s RGB color extracted and converted to hex.
The pixel data is sent to the client in the format [{x, y, hex_color}, ...].


Canvas Rendering:
The canvas displays the pixelated image as colored squares.
The rendering fits the 512x512 canvas, with square sizes calculated based on grid dimensions.
The canvas clears before rendering a new image.


Performance:
Processing completes within 2 seconds for a 10MB image with a 64x64 grid.
Processing completes within 5 seconds for a 128x128 grid.
Rendering completes within 100ms for a 64x64 grid and 500ms for a 128x128 grid.


Error Handling:
Displays “No file uploaded” if no file is selected.
Displays “Failed to process image” with details for processing errors.
Displays “Invalid grid size” for negative, zero, or excessively large inputs (>256).



7. Risks and Mitigations

Risk: Large grid sizes (e.g., 256x256) cause performance issues.
Mitigation: Cap grid size at 256x256; provide user warnings for grids >128x128; optimize image processing with Mogrify.


Risk: ImageMagick not installed or misconfigured.
Mitigation: Provide clear setup instructions; check ImageMagick availability in CI/CD.


Risk: Browser compatibility issues with canvas rendering.
Mitigation: Test on Chrome, Firefox, Safari, and Edge; use standard canvas APIs.


Risk: Security issues with file uploads or large grid sizes.
Mitigation: Validate file types, sizes, and grid inputs; use temporary files and secure deletion.



8. Future Enhancements

Support dynamic canvas resizing based on grid size or user input.
Add color filter options (e.g., grayscale, sepia).
Implement zoom/pan on the canvas for large grids.
Add export functionality to save the pixelated image as a PNG.
Provide a preview of the pixelated image before final rendering.

9. Testing Requirements

Unit Tests:
Test process_image/1 for correct pixel data generation across grid sizes (16x16, 64x64, 128x128).
Test RGB-to-hex conversion.
Test grid size validation.


Integration Tests:
Test upload, grid size selection, and rendering flow in LiveView.
Verify error handling for invalid uploads and grid sizes.


Browser Tests:
Test canvas rendering on Chrome, Firefox, Safari, and Edge for various grid sizes.


Performance Tests:
Measure processing time for 10MB images with 64x64 and 128x128 grids.
Measure rendering time for 64x64 and 128x128 grids.
Test server load with 100 concurrent uploads.



10. Documentation

Include setup instructions for ImageMagick and dependencies.
Document configuration options (grid size, canvas size, max file size).
Provide a user guide for uploading, selecting grid size, and viewing pixelated images.
Document performance considerations for large grid sizes.

11. Stakeholders

Product Owner: Defines feature requirements and priorities.
Developers: Implement the feature and tests.
Users: End users who upload and view pixelated images with customizable grid sizes.
DevOps: Ensure ImageMagick is installed on deployment servers.

12. Timeline

Design and Development: 1-2 weeks (including testing for multiple grid sizes).
Review and Feedback: 3-5 days.
Deployment: 1 day (after PR approval).

