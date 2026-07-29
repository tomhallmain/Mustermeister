/**
 * Regression test for the vendor/javascript/sortablejs.js patch: a large
 * emptyInsertThreshold (needed so a sparse/empty kanban column stays
 * droppable at any scroll depth on a tall board) used to inflate an empty
 * list's hit box by the same amount on all 4 sides, not just vertically -
 * so it also bled sideways into neighboring columns and stole the drop
 * target mid-drag. The patched _detectNearestEmptySortable caps the
 * horizontal inflation independently of the (still large) vertical one.
 *
 * This drives the real, patched _detectNearestEmptySortable directly
 * (exposed only for tests, see the vendor file) instead of simulating a
 * full native HTML5 drag gesture, since jsdom's DataTransfer/DnD support
 * is too incomplete for that to be reliable.
 */
const Sortable = require("../../vendor/javascript/sortablejs.js").default;

describe("vendor/javascript/sortablejs.js emptyInsertThreshold patch", () => {
  let populatedColumn; // e.g. "In Progress" - has a card, is the real drop target
  let emptyColumn; // e.g. "Complete" - empty, positioned to its right with an 8px gap
  let instances;

  beforeEach(() => {
    document.body.innerHTML = `
      <div id="populated"><div data-task-id="1">Task</div></div>
      <div id="empty"></div>
    `;
    populatedColumn = document.getElementById("populated");
    emptyColumn = document.getElementById("empty");

    // Mirrors the real kanban board: 256px-wide columns (w-64) separated by
    // an 8px gap (space-x-2). populatedColumn is tall (a long backlog);
    // emptyColumn is short, as an empty column naturally renders before
    // flex-1 stretches it to match - both are relevant here, since
    // _detectNearestEmptySortable inflates from the list's own real rect.
    populatedColumn.getBoundingClientRect = () => ({
      left: 300,
      right: 556,
      top: 100,
      bottom: 3000,
      width: 256,
      height: 2900,
    });
    emptyColumn.getBoundingClientRect = () => ({
      left: 564,
      right: 820,
      top: 100,
      bottom: 140,
      width: 256,
      height: 40,
    });

    instances = [
      new Sortable(populatedColumn, { group: "tasks", emptyInsertThreshold: 5000 }),
      new Sortable(emptyColumn, { group: "tasks", emptyInsertThreshold: 5000 }),
    ];
  });

  afterEach(() => {
    instances.forEach((instance) => instance.destroy());
  });

  test("does not claim a point squarely inside the neighboring populated column", () => {
    // 6px from the populated column's own right edge, still 14px away from
    // the empty column's real left edge - clearly hovering the populated
    // column. Unpatched (threshold applied on all 4 sides), this would
    // have matched the empty column anyway since 5000 covers the whole
    // board horizontally too.
    const hit = Sortable._detectNearestEmptySortableForTests(550, 300);
    expect(hit).toBeUndefined();
  });

  test("still finds the empty column far below its own short box", () => {
    // The empty column is only 40px tall, but a large emptyInsertThreshold
    // must still make it droppable far down a page scrolled to match a
    // long neighboring column - this is the vertical reach the large
    // threshold value exists to preserve.
    const hit = Sortable._detectNearestEmptySortableForTests(700, 3000);
    expect(hit).toBe(emptyColumn);
  });

  test("still finds the empty column just past its own real horizontal edge", () => {
    const hit = Sortable._detectNearestEmptySortableForTests(830, 120);
    expect(hit).toBe(emptyColumn);
  });

  test("does not find the empty column well past its own real horizontal edge", () => {
    const hit = Sortable._detectNearestEmptySortableForTests(1200, 120);
    expect(hit).toBeUndefined();
  });
});
