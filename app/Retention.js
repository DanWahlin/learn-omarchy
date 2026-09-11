function eligibleLessons(course, stepResults, stepCredits) {
    if (!course || !Array.isArray(course.lessons)) return [];
    var results = stepResults || {};
    var credits = stepCredits || {};
    return course.lessons.filter(function(lesson) {
        if (lesson.mixedPractice !== true || lesson.kind === "welcome" || !lesson.steps.length) return false;
        // A future curriculum opt-in cannot silently add capture, locking or microphone tasks.
        if (lesson.steps.some(function(step) {
            return step.kind === "practice" && ["app-search", "clipboard", "compose"].indexOf(step.practice) === -1;
        })) return false;
        return lesson.steps.every(function(step) {
            return step.optional || credits[step.id] === true ||
                ["introduced", "assisted", "practiced"].indexOf(results[step.id]) !== -1;
        });
    });
}

function mixedPracticePlan(course, stepResults, stepCredits, limit, random) {
    var lessons = eligibleLessons(course, stepResults, stepCredits).slice();
    var nextRandom = typeof random === "function" ? random : Math.random;
    for (var i = lessons.length - 1; i > 0; i--) {
        var value = Number(nextRandom());
        if (!isFinite(value) || value < 0 || value >= 1) value = 0;
        var j = Math.floor(value * (i + 1));
        var item = lessons[i]; lessons[i] = lessons[j]; lessons[j] = item;
    }
    var count = Number.isInteger(limit) && limit > 0 ? limit : 3;
    // Keep entire lesson blocks: launch, dependent outcomes and cleanup share the original runtime.
    return lessons.slice(0, count).map(function(lesson) { return lesson.id; });
}

function lessonIndex(course, id) {
    if (!course || !Array.isArray(course.lessons)) return -1;
    return course.lessons.findIndex(function(lesson) { return lesson.id === id; });
}
