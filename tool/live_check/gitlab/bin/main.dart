import 'dart:io';

import 'package:graphql/client.dart';
import 'package:live_check_gitlab/graphql/generated/index.dart';

void check(bool ok, String what) {
  print('${ok ? 'OK  ' : 'FAIL'} $what');
  if (!ok) exitCode = 1;
}

String who(UserBits u) => '${u.name} (@${u.username})';

String issueLine(IssueBits i) => '#${i.iid} [${i.state.name}] ${i.title} '
    '(${i.labels?.nodes?.map((l) => l?.title).join(', ')})';

Future<void> main() async {
  final client = GraphQLClient(
    link: HttpLink('https://gitlab.com/api/graphql'),
    cache: GraphQLCache(possibleTypes: possibleTypes),
    queryRequestTimeout: const Duration(seconds: 30),
  );
  const path = 'gitlab-org/gitlab';

  final project = await client.projectIssuesData(const ProjectIssuesVariables(
          fullPath: path, first: 3, state: IssuableState.opened)
      .toJson());
  check(project != null, 'project: ${project?.name}');
  check(project?.visibility == 'public', 'visibility: ${project?.visibility}');
  final issues = project!.issues!;
  check(issues.nodes?.length == 3, 'first: 3 gives ${issues.nodes?.length}');
  check(issues.count > 0, 'count: ${issues.count}');
  check(issues.pageInfo.hasNextPage && issues.pageInfo.endCursor != null,
      'pageInfo has a next page');
  for (final issue in issues.nodes!) {
    print('     ${issueLine(issue!)} by ${who(issue.author)}');
  }
  check(issues.nodes!.every((i) => i!.state == IssueState.opened),
      'state filter applied');
  check(
      issues.edges!.map((e) => e!.node!.iid).join() ==
          issues.nodes!.map((n) => n!.iid).join(),
      'edges and nodes agree');

  final iid = issues.nodes!.first!.iid;
  final notes = await client
      .issueNotesData(IssueNotesVariables(fullPath: path, iid: iid).toJson());
  final issue = notes?.issue;
  check(issue?.iid == iid, 'issue $iid: ${issue?.title}');
  for (final note in issue!.notes.nodes!) {
    final target = switch (note?.discussion?.noteable) {
      IssueNotes_Project_Issue_Notes_Nodes_Discussion_Noteable_OnIssue(
        :final iid
      ) =>
        'issue #$iid',
      IssueNotes_Project_Issue_Notes_Nodes_Discussion_Noteable_OnMergeRequest(
        :final iid
      ) =>
        'MR !$iid',
      IssueNotes_Project_Issue_Notes_Nodes_Discussion_Noteable_Other(
        :final typename
      ) =>
        'other $typename',
      null => 'no discussion',
    };
    print('     note by ${note?.author == null ? '?' : who(note!.author!)}'
        ' on $target');
  }
  check(
      issue.notes.nodes!.every((n) =>
          n?.discussion?.noteable == null ||
          n!.discussion!.noteable
              is IssueNotes_Project_Issue_Notes_Nodes_Discussion_Noteable_OnIssue),
      'union resolved to the issue');

  // An issue from the first query and one from the second fit IssueBits.
  final both = <IssueBits>[issues.nodes!.first!, issue];
  check(both.map(issueLine).toSet().length == 1,
      'fragment interface across queries');
}
