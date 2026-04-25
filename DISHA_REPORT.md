# PROJECT REPORT: DISHA
## An Augmented Reality Framework for High-Precision Indoor Navigation

---

## 1. INTRODUCTION
The ubiquitous reliance on Global Positioning System (GPS) technology presents a critical limitation in modern navigation: the "Last-Mile" problem in indoor environments. Because GPS relies on low-power satellite signals that require a clear line of sight, it suffers from severe attenuation and multipath interference when penetrating complex architectural structures such as university campuses, subterranean transit hubs, multi-story hospitals, and retail malls. As a result, users are often guided accurately to the entrance of a building, only to be left without guidance once inside.

"Disha" is a specialized Augmented Reality (AR) navigation application engineered to bridge this gap. Operating entirely independently of GPS, Disha leverages Visual SLAM (Simultaneous Localization and Mapping) combined with rigorous coordinate normalization. By mapping the physical environment through the device's camera and inertial sensors, the application allows users to generate high-precision, localized spatial maps. These maps are then utilized to project intuitive, 3D visual cues directly into the user's physical space, offering a seamless, spatially-aware routing experience.

## 2. CORE OBJECTIVES
The development of Disha was driven by five foundational objectives aimed at overcoming the physical and computational limitations of consumer hardware:

*   **Absolute Spatial Accuracy in GPS-Denied Zones:** To engineer a localization system that maintains sub-meter accuracy indoors by relying entirely on visual odometry and device-native inertial measurement units (IMUs).
*   **Deterministic Waypoint Pinning:** To replace error-prone automatic mapping with a robust, human-in-the-loop "Waypoint Pinning" system. This ensures map nodes are intentionally placed at critical junctions, drastically reducing the accumulation of mapping errors over large distances.
*   **Advanced Signal Processing for Sensor Stability:** To counteract inherent hardware drift and sensor jitter by implementing sophisticated mathematical smoothing, specifically using Exponential Moving Average (EMA) filters to sanitize raw accelerometer and gyroscope data.
*   **Cognitively Intuitive AR Interface:** To reduce the cognitive load of navigation by overlaying 3D directional vectors (AR arrows) onto the physical floor, supplemented by real-time spatial audio cues for eyes-free guidance.
*   **Persistent Spatial Graphing:** To ensure that once an environment is mapped, the topological graph is efficiently serialized and stored locally, allowing for instant retrieval and navigation upon subsequent visits without requiring the user to remap the area.

## 3. TOOLS & TECHNOLOGIES ARCHITECTURE
The technology stack was selected to balance cross-platform efficiency with low-level hardware access necessary for AR tracking.

*   **Application Framework:** Flutter (Provides a unified, high-performance UI layer operating at 60fps).
*   **Core Logic Language:** Dart (Handles asynchronous event loops, pathfinding algorithms, and state execution).
*   **Native AR Engines:** Google ARCore (Android) and Apple ARKit (iOS), bridged into Flutter via custom Platform Channels to execute hardware-accelerated SLAM.
*   **State Management:** Flutter BLoC (Business Logic Component). Ensures strict separation of the UI layer from the heavy, continuous stream of spatial data, preventing UI thread blocking.
*   **Spatial Mathematics:** VectorMath library. Utilized for 64-bit coordinate geometry, handling quaternion rotations, matrix transformations, and Euler angle conversions necessary for 3D rendering.
*   **Data Persistence:** Shared Preferences for lightweight, high-speed read/write of the local directed graphs and user settings.
*   **Geospatial Indexing:** Uber’s H3 Hexagonal Hierarchical Spatial Index. Used to segment the mapped environment into hexagonal grids, allowing for hyper-efficient spatial queries and node lookups.
*   **Accessibility:** Flutter TTS (Text-to-Speech) for dynamically generated auditory routing instructions.

## 4. SYSTEM ARCHITECTURE & PROJECT DESCRIPTION
Disha's foundational logic is structured around a Directed Spatial Graph, where physical locations act as nodes, and the walkable paths between them act as weighted edges.

### 4.1. Absolute Spatial Anchoring
AR systems inherently boot up with a relative origin. To navigate a physical building consistently, the app must bind its digital coordinate system to the real world. Disha utilizes a QR-code calibration protocol. By scanning a strategically placed, fixed QR code at the building's entrance, the app establishes an absolute origin at (0,0,0) in AR space. All subsequent spatial data is calculated relative to this physical anchor point.

### 4.2. Coordinate Normalization
A major challenge in mobile AR is the unpredictable orientation of the user's device. To maintain a consistent graph regardless of how the phone is held, Disha normalizes all captured coordinates into a universal "Map Space." This is achieved by querying the device's magnetometer to establish true North, applying a rotation matrix to align the localized AR session with global cardinal directions.

### 4.3. The Stability Layer & Dynamic Anchor Sync
Raw IMU data is notoriously noisy, leading to "drift," where the AR system believes the user is moving even when stationary. Disha solves this using two methods:
1.  **Vibration Gating (EMA):** An Exponential Moving Average filter (0.15 factor) sanitizes raw heading data, suppressing jitter and হাত Hand tremors.
2.  **Dynamic Anchor Sync:** Instead of static positioning, Disha creates a persistent ARCore **Anchor** at the calibration point. This Anchor acts as a physical "pin" in the real world. If the ARCore SLAM engine re-calculates the room geometry, the entire navigation graph shifts with the anchor, maintaining perfect, drift-free synchronization.

### 4.4. A* Algorithmic Pathfinding
Once a map is generated, navigation relies on the A* (A-Star) search algorithm to determine the optimal route. The engine calculates the shortest path utilizing the standard cost function: f(n) = g(n) + h(n). The algorithm is heavily modified to incorporate accessibility weights, allowing it to bypass stairs or narrow corridors if a "wheelchair-accessible" parameter is engaged by the user.

## 5. USER INTERFACE & SCREENSHOT DESCRIPTIONS
*   **[Calibration Interface]:** Features a darkened camera overlay with a high-contrast targeting reticle. A status banner reads "Awaiting Spatial Calibration." Once the QR code is detected, a green volumetric mesh briefly flashes over the environment to confirm anchor lock.
*   **[Mapping Heads-Up Display (HUD)]:** A streamlined interface used during the map-creation phase. It features a prominent floating action button labeled "Drop Waypoint." A live telemetry dashboard at the top of the screen displays real-time metrics: current X/Y/Z coordinates, steps taken, and session distance in meters.
*   **[Live Navigation View]:** The core AR experience. The camera feed shows the physical world with a glowing, high-contrast 3D path rendered directly onto the floor. A dynamic chevron arrow sits in the lower center of the screen, actively rotating to point toward the next node.
*   **[Arrival & Analytics Overlay]:** A modal screen that interrupts the AR view upon reaching the destination. It confirms arrival and displays post-navigation analytics, including route efficiency, time elapsed, and total distance traveled.

## 6. OPERATIONAL WORKFLOW
1.  **Environmental Calibration:** The user launches Disha and approaches a recognized physical anchor (the QR code). The system reads the spatial constraints, initializes the SLAM tracking state, and aligns its internal coordinate matrix with the physical architecture of the building.
2.  **Human-in-the-loop Mapping:** For unmapped environments, the user acts as the surveyor. The user walks the desired route, manually triggering the "Mark Corner" function at every physical turn or intersection. The app drops high-precision digital nodes at these coordinates.
3.  **Graph Processing & Pathfinding:** Upon requesting directions, the user selects a destination from the locally stored graph. The routing engine parses the directed graph, executes the A* algorithm, and highlights the sequence of edges that yield the lowest traversal cost.
4.  **AR Rendering & Execution:** The app translates the calculated path into 3D geometry. Disha uses atan2 trigonometric functions to continuously calculate the angle between the user's current vector and the target waypoint. This logic instantly updates the orientation of the 3D directional arrow.

## 7. CONCLUSION
"Disha" validates a crucial hypothesis in modern spatial computing: highly reliable, professional-grade indoor navigation can be achieved on standard consumer smartphones. By deliberately shifting away from fully automated, heavily drift-susceptible tracking methods, and instead adopting a user-assisted "waypoint pinning" methodology, the system eliminates the compounding errors typical of mobile SLAM.

## 8. FUTURE SCOPE & SCALABILITY
*   **Z-Axis/Multi-Floor Integration:** Utilizing the device's built-in barometer to track minor fluctuations in atmospheric pressure for elevation changes.
*   **Distributed Mapping via Cloud Anchors:** Transitioning from local Shared Preferences to a cloud-hosted graph database for crowd-sourced mapping.
*   **IoT & Smart Building Handshakes:** Integrating MQTT protocols to allow the app to communicate with Bluetooth Low Energy (BLE) beacons.
*   **Computer Vision Validation:** Implementing neural networks (e.g., YOLO variants) to recognize physical context markers—such as room number placards—for auto-correction.

## 9. REFERENCES
*   Google Developers. (n.d.). ARCore Fundamentals: Environmental Understanding and Motion Tracking.
*   Hart, P. E., Nilsson, N. J., & Raphael, B. (1968). A Formal Basis for the Heuristic Determination of Minimum Cost Paths.
*   Flutter Platform Integration. (n.d.). Writing custom platform-specific code.
*   VectorMath Dart Package. (n.d.). Matrix and Quaternion operations for 3D coordinate transformations.