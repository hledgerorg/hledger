// A prototype of a custom issues list/dashboard.
// Copy this file (app.orig.js) to app.js for safety,
// and in app.js, set token to a github personal access token
// from https://github.com/settings/personal-access-tokens/new .
// Then open index.html in a browser.

const token = '';


const getIssues = (name) => {
    // https://docs.github.com/en/rest/issues/issues?apiVersion=2022-11-28#list-repository-issues
    // up to 100 most open bugs, most recently created first  XXX with a severityN label
    fetch(`https://api.github.com/repos/${name}/issues?per_page=100&labels=A-BUG`, //&label=severity1,severity2,severity3,severity4,severity5`,
        {
            headers: {
                'Accept': 'application/vnd.github.v3+json',
                'Authorization': `token ${token}`
            }
        })
        .then(response => response.json())
        .then(data => {
            // console.log(data)
            showIssues(data);
        })
        .catch(error => console.error(error))
}

const showIssues = (data) => {
    let t = document.getElementById('issues');
    let r = t.insertRow();
    r.innerHTML = `<th>User pain</th>`;
    
    for (let i in data) {
        let r = t.insertRow();
        let issue = data[i];

        c = r.insertCell();
        c.style = `white-space:nowrap; font-weight:bold;`;
        let imp = issueImpact(issue);
        let sev = issueSeverity(issue);
        let maxscore = 25; // max impact * max severity
        let pain = (sev && imp) ? sev * imp / maxscore : '';
        c.innerHTML = pain ? `${pain}` : '';

        c = r.insertCell();
        c.innerHTML = `<a href="${issue.html_url}">#${issue.number} ${issue.title}</a>`;

        c = r.insertCell();
        c.innerHTML = '';

        let sortedlabels = issue.labels.toSorted( (a,b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase()) );
        for (let j in sortedlabels) { c.innerHTML += showLabel(sortedlabels[j]); }

        // c = r.insertCell();
        // c.innerHTML = `${iss.user.login}`;
    }
}

const issueFindLabelWithPrefix = (issue, prefix) => {
    for (let i in issue.labels) {
        let l = issue.labels[i];
        if (l.name.startsWith(prefix)) {return l.name;}
    }
    return '';
}


const issueSeverity = (issue) => {
    let l = issueFindLabelWithPrefix(issue, 'severity');
    return l ? l.replace('severity','') : '';
}

const issueImpact = (issue) => {
    let l = issueFindLabelWithPrefix(issue, 'impact');
    return l ? l.replace('impact','') : '';
}

const showLabel = (label) => {
    cls = label.name.startsWith('severity') || label.name.startsWith('impact') ? 'paletag' : 'tag';
    return ` <span class="${cls}" style="background-color:#${label.color};">` + label.name + '</span>';
}

getIssues('hledgerorg/hledger');
