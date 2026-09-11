function address(client) {
    return String(client && client.address || "").toLowerCase().replace(/^0x/, "");
}

function rectangle(client) {
    if (!client || !address(client) || client.mapped === false || client.hidden === true ||
        !Array.isArray(client.at) || !Array.isArray(client.size) ||
        client.at.length !== 2 || client.size.length !== 2 ||
        !client.at.concat(client.size).every(function(value) { return typeof value === "number" && isFinite(value); }) ||
        client.size[0] <= 0 || client.size[1] <= 0 ||
        typeof client.floating !== "boolean" || !Number.isInteger(client.fullscreen) || client.fullscreen < 0 ||
        !Number.isInteger(client.monitor) || client.monitor < 0 ||
        !client.workspace || !Number.isInteger(client.workspace.id)) return null;
    return {
        address: address(client), at: client.at.slice(), size: client.size.slice(),
        workspace: client.workspace.id, floating: client.floating,
        fullscreen: client.fullscreen, monitor: client.monitor
    };
}

function sameContext(before, after) {
    return Boolean(before && after && before.address === after.address &&
        before.workspace === after.workspace && before.monitor === after.monitor &&
        before.floating === after.floating && before.fullscreen === after.fullscreen);
}

function resized(before, client) {
    var after = rectangle(client);
    return sameContext(before, after) &&
        (Math.abs(after.size[0] - before.size[0]) >= 2 || Math.abs(after.size[1] - before.size[1]) >= 2);
}

function orientation(first, peer) {
    if (!first || !peer || first.address === peer.address ||
        first.workspace !== peer.workspace || first.monitor !== peer.monitor ||
        first.floating !== false || peer.floating !== false ||
        first.fullscreen !== 0 || peer.fullscreen !== 0) return "";
    var overlapX = Math.min(first.at[0] + first.size[0], peer.at[0] + peer.size[0]) - Math.max(first.at[0], peer.at[0]);
    var overlapY = Math.min(first.at[1] + first.size[1], peer.at[1] + peer.size[1]) - Math.max(first.at[1], peer.at[1]);
    if (overlapX <= 0 && overlapY > 2) return "horizontal";
    if (overlapY <= 0 && overlapX > 2) return "vertical";
    return "";
}

function capture(client, peer) {
    return { first: rectangle(client), peer: rectangle(peer) };
}

function splitChanged(before, client, peer) {
    if (!before) return false;
    var after = capture(client, peer);
    if (!sameContext(before.first, after.first) || !sameContext(before.peer, after.peer)) return false;
    var original = orientation(before.first, before.peer);
    var current = orientation(after.first, after.peer);
    return original !== "" && current !== "" && original !== current;
}
