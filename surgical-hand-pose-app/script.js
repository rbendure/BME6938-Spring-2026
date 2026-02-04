// --- Three.js Initialization ---
const canvas = document.querySelector('.output_canvas');
const scene = new THREE.Scene();

// Camera setup
const camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.1, 1000);
camera.position.z = 20; // Move camera back to view the scene

// Renderer (Alpha true for transparency over video)
const renderer = new THREE.WebGLRenderer({ canvas: canvas, alpha: true, antialias: true });
renderer.setSize(window.innerWidth, window.innerHeight);
renderer.setPixelRatio(window.devicePixelRatio);

// Lighting
const ambientLight = new THREE.AmbientLight(0xffffff, 0.6);
scene.add(ambientLight);
const directionalLight = new THREE.DirectionalLight(0xffffff, 0.8);
directionalLight.position.set(0, 10, 10);
scene.add(directionalLight);

// --- Object Management ---
let objects = [];

// Create Cylinder
function createCylinder(height, position, cuttable = true) {
    const geometry = new THREE.CylinderGeometry(1, 1, height, 32);
    const material = new THREE.MeshPhongMaterial({ color: 0x0000ff }); // Blue
    const cylinder = new THREE.Mesh(geometry, material);
    cylinder.position.copy(position);
    cylinder.userData = { type: 'cylinder', cuttable: cuttable, baseScale: 1.0 };
    
    scene.add(cylinder);
    objects.push(cylinder);
    return cylinder;
}

// Create Scalpel
function createScalpel(position) {
    // Handle
    const handleGeo = new THREE.BoxGeometry(0.5, 3, 0.2);
    const handleMat = new THREE.MeshPhongMaterial({ color: 0x888888 }); // Grey
    const handle = new THREE.Mesh(handleGeo, handleMat);

    // Blade
    const bladeGeo = new THREE.BoxGeometry(0.3, 1.5, 0.05);
    const bladeMat = new THREE.MeshPhongMaterial({ color: 0xc0c0c0 }); // Silver
    const blade = new THREE.Mesh(bladeGeo, bladeMat);
    blade.position.y = 2.25; // Stack on top of handle (3/2 + 1.5/2)

    // Group them
    const scalpelGroup = new THREE.Group();
    scalpelGroup.add(handle);
    scalpelGroup.add(blade);
    scalpelGroup.position.copy(position);
    
    scalpelGroup.userData = { type: 'tool', cuttable: false };

    scene.add(scalpelGroup);
    objects.push(scalpelGroup);
    return scalpelGroup;
}

// Initialize Scene
createCylinder(4, new THREE.Vector3(-3, 0, 0), true); // Left side
createScalpel(new THREE.Vector3(3, 0, 0)); // Right side

// Interaction State
let grabbedObject = null;
let isPinching = false;
let pinchStartDistance = 0;
let initialObjectScale = 1;

// Constants
const GRAB_THRESH = 0.05; // Tight pinch to grab
const DROP_THRESH_TOOL = 0.1; // Normal drop for tool
const DROP_THRESH_OBJ = 0.3; // Wide drop for magnifying object
const GRAB_RADIUS = 3.0;
const MAX_SCALE = 3.0; // Max magnification 3x
const MIN_SCALE = -3.0; // Min magnification -3x (inverted)

// Handle window resize
window.addEventListener('resize', () => {
    camera.aspect = window.innerWidth / window.innerHeight;
    camera.updateProjectionMatrix();
    renderer.setSize(window.innerWidth, window.innerHeight);
});

// Animation Loop
function animate() {
    requestAnimationFrame(animate);
    renderer.render(scene, camera);
}
animate();


// --- MediaPipe Hands Initialization ---
const videoElement = document.querySelector('.input_video');

const hands = new Hands({locateFile: (file) => {
    return `https://cdn.jsdelivr.net/npm/@mediapipe/hands/${file}`;
}});

hands.setOptions({
    maxNumHands: 1,
    modelComplexity: 1,
    minDetectionConfidence: 0.7,
    minTrackingConfidence: 0.7
});

hands.onResults(onResults);

// --- Camera Utils Initialization ---
const cameraUtils = new Camera(videoElement, {
    onFrame: async () => {
        await hands.send({image: videoElement});
    },
    width: 1280,
    height: 720
});
cameraUtils.start();


// --- Logic Handling ---

function getThreeJSCoord(normalizedX, normalizedY) {
    const dist = camera.position.z;
    const vFOV = THREE.Math.degToRad(camera.fov);
    const visibleHeight = 2 * Math.tan(vFOV / 2) * dist;
    const visibleWidth = visibleHeight * camera.aspect;

    const targetX = (0.5 - normalizedX) * visibleWidth;
    const targetY = (0.5 - normalizedY) * visibleHeight;

    return new THREE.Vector3(targetX, targetY, 0); 
}

function onResults(results) {
    if (results.multiHandLandmarks && results.multiHandLandmarks.length > 0) {
        const landmarks = results.multiHandLandmarks[0];

        const thumbTip = landmarks[4];
        const indexTip = landmarks[8];

        // 1. Calculate Pinch Distance (2D normalized)
        const distance = Math.sqrt(
            Math.pow(thumbTip.x - indexTip.x, 2) +
            Math.pow(thumbTip.y - indexTip.y, 2)
        );

        // 2. Map positions to 3D World Space
        const thumbPos = getThreeJSCoord(thumbTip.x, thumbTip.y);
        const indexPos = getThreeJSCoord(indexTip.x, indexTip.y);
        const pinchMidpoint = new THREE.Vector3().addVectors(thumbPos, indexPos).multiplyScalar(0.5);

        // Calculate Angle for Rotation (Z-axis rotation based on finger angle)
        const dx = indexTip.x - thumbTip.x;
        const dy = indexTip.y - thumbTip.y;
        const rotationZ = -Math.atan2(dx, dy); // Simple 2D rotation

        // --- State Machine ---

        if (!grabbedObject) {
            // IDLE: Check for Grab
            if (distance < GRAB_THRESH) {
                // Attempt Create Start
                let closestObj = null;
                let minDist = Infinity;

                for (let obj of objects) {
                    const d = pinchMidpoint.distanceTo(obj.position);
                    if (d < minDist) {
                        minDist = d;
                        closestObj = obj;
                    }
                }

                if (closestObj && minDist < GRAB_RADIUS) {
                    grabbedObject = closestObj;
                    isPinching = true;
                    pinchStartDistance = distance;
                    initialObjectScale = closestObj.scale.x; // Uniform scale assumption
                    
                    // Visual feedback
                    if (closestObj.userData.type === 'cylinder') {
                        closestObj.material.color.setHex(0xff0000); // Red
                    }
                }
            }
        } else {
            // HOLDING Logic
            
            // Move object
            grabbedObject.position.lerp(pinchMidpoint, 0.2);
            grabbedObject.rotation.z = rotationZ;

            if (grabbedObject.userData.type === 'tool') {
                // --- SCALPEL BEHAVIOR ---
                
                // Check Cuts
                // Scalpel Tip calculation:
                // Tip is +2.25 (handle center to blade base) + 0.75 (half blade) = +3.0 local Y (approx)
                // We need to transform local tip vector to world space
                const tipOffset = new THREE.Vector3(0, 3.0, 0);
                tipOffset.applyEuler(grabbedObject.rotation);
                const tipPos = new THREE.Vector3().addVectors(grabbedObject.position, tipOffset);

                checkScalpelCut(tipPos);

                // Drop Condition (Normal Pinch release)
                if (distance > DROP_THRESH_TOOL) {
                    dropObject();
                }

            } else {
                // --- CYLINDER BEHAVIOR (MAGNIFICATION) ---
                
                // Magnification Logic:
                // Current Scale = Initial Scale + (Current Dist - Start Dist) * Sensitivity
                // Let's use a ratio multiplier with clamp
                let ratio = distance / 0.05; // normalize to the grab threshold
                
                let newScale = initialObjectScale * ratio;
                
                // Clamp features
                if (newScale > MAX_SCALE) newScale = MAX_SCALE;
                if (newScale < MIN_SCALE) newScale = MIN_SCALE; // Allow negative scale

                grabbedObject.scale.set(newScale, newScale, newScale);

                // Drop Condition (Wait for Wide Open hand)
                if (distance > DROP_THRESH_OBJ) {
                    dropObject();
                }
            }
        }
    }
}

function dropObject() {
    if (grabbedObject) {
        if (grabbedObject.userData.type === 'cylinder') {
             grabbedObject.material.color.setHex(0x0000ff); // Blue
        }
        grabbedObject = null;
        isPinching = false;
    }
}

function checkScalpelCut(bladeTipPos) {
    // Iterate backwards
    for (let i = objects.length - 1; i >= 0; i--) {
        const obj = objects[i];

        if (obj.userData.type === 'cylinder' && obj.userData.cuttable) {
            // Distance Check
            const dx = bladeTipPos.x - obj.position.x;
            const dy = Math.abs(bladeTipPos.y - obj.position.y);
            const dz = bladeTipPos.z - obj.position.z;
            
            // XZ check (Cylinder radius is default 1 * scale)
            const radius = 1.0 * Math.abs(obj.scale.x);
            const distXZ = Math.sqrt(dx*dx + dz*dz);

            // Cut Logic: Tip inside radius AND near vertical center
            if (distXZ < (radius * 1.2) && dy < 0.5) {
                performSplit(obj, i);
            }
        }
    }
}

function performSplit(obj, index) {
    scene.remove(obj);
    objects.splice(index, 1); 

    const originalHeight = obj.geometry.parameters.height;
    const currentScale = obj.scale.x; // Uniform scale
    const scaledHeight = originalHeight * currentScale;

    // Use absolute currentScale to avoid negative heights
    const absScale = Math.abs(currentScale);
    const newHeight = originalHeight / 2;
    const separation = 0.8 * absScale; // Ensure separation matches visual scale

    // Top Half
    const topPos = obj.position.clone();
    topPos.y += (scaledHeight / 4) + separation; 
    // Wait, if scaledHeight is negative (inverted), the pos calc works purely on visual
    // Let's rely on obj position.
    
    const topObj = createCylinder(newHeight, topPos, true);
    topObj.scale.copy(obj.scale);

    // Bottom Half
    const botPos = obj.position.clone();
    botPos.y -= (scaledHeight / 4) + separation;
    const botObj = createCylinder(newHeight, botPos, true);
    botObj.scale.copy(obj.scale);
}
// End of file
