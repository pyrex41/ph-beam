/**
 * LayerContextMenu Hook for Phoenix LiveView
 *
 * Handles right-click context menu for layer items in the layers panel.
 * Provides options for layer reordering (bring to front, send to back, etc.)
 */
export default {
  mounted() {
    console.log('[LayerContextMenu] Mounted on container');

    // Use event delegation - listen at container level
    this.contextMenuHandler = (e) => {
      // Find the closest layer-item element
      const layerItem = e.target.closest('.layer-item');

      if (layerItem) {
        console.log('[LayerContextMenu] Context menu on layer item');
        e.preventDefault();
        e.stopPropagation();

        // Get object ID from data attribute
        const objectId = parseInt(layerItem.dataset.layerId);
        console.log('[LayerContextMenu] Object ID:', objectId);

        // Show custom context menu
        this.showContextMenu(e.clientX, e.clientY, objectId);
      }
    };

    this.el.addEventListener('contextmenu', this.contextMenuHandler);

    // Close context menu when clicking elsewhere
    this.clickHandler = (e) => {
      const contextMenu = document.getElementById('layer-context-menu');
      if (contextMenu && !contextMenu.contains(e.target)) {
        this.hideContextMenu();
      }
    };
    document.addEventListener('click', this.clickHandler);
  },

  showContextMenu(x, y, objectId) {
    // Store the current object ID
    this.currentObjectId = objectId;

    // Remove any existing context menu
    this.hideContextMenu();

    // Create context menu
    const menu = document.createElement('div');
    menu.id = 'layer-context-menu';
    menu.className = 'fixed bg-white rounded-lg shadow-lg border border-gray-200 py-1 z-50';
    menu.style.left = `${x}px`;
    menu.style.top = `${y}px`;

    // Menu items
    const menuItems = [
      { label: 'Bring to Front', icon: '⬆⬆', event: 'bring_to_front' },
      { label: 'Move Forward', icon: '⬆', event: 'move_forward' },
      { label: 'Move Backward', icon: '⬇', event: 'move_backward' },
      { label: 'Send to Back', icon: '⬇⬇', event: 'send_to_back' },
    ];

    menuItems.forEach((item) => {
      const menuItem = document.createElement('button');
      menuItem.className = 'w-full px-4 py-2 text-left text-sm hover:bg-gray-100 flex items-center gap-2';
      menuItem.innerHTML = `
        <span class="text-gray-500">${item.icon}</span>
        <span>${item.label}</span>
      `;
      menuItem.addEventListener('click', () => {
        this.handleMenuAction(item.event, objectId);
        this.hideContextMenu();
      });
      menu.appendChild(menuItem);
    });

    document.body.appendChild(menu);

    // Adjust position if menu goes off-screen
    const rect = menu.getBoundingClientRect();
    if (rect.right > window.innerWidth) {
      menu.style.left = `${window.innerWidth - rect.width - 10}px`;
    }
    if (rect.bottom > window.innerHeight) {
      menu.style.top = `${window.innerHeight - rect.height - 10}px`;
    }
  },

  hideContextMenu() {
    const menu = document.getElementById('layer-context-menu');
    if (menu) {
      menu.remove();
    }
  },

  handleMenuAction(action, objectId) {
    console.log('[LayerContextMenu] Handling action:', action, 'for object:', objectId);
    // Push event to server with object ID
    this.pushEvent(action, { object_id: objectId });
  },

  destroyed() {
    this.hideContextMenu();
    if (this.contextMenuHandler) {
      this.el.removeEventListener('contextmenu', this.contextMenuHandler);
    }
    if (this.clickHandler) {
      document.removeEventListener('click', this.clickHandler);
    }
  }
};
