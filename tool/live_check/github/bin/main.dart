import 'dart:io';

import 'package:graphql/client.dart';
import 'package:live_check_github/graphql/generated/index.dart';

void check(bool ok, String what) {
  print('${ok ? 'OK  ' : 'FAIL'} $what');
  if (!ok) exitCode = 1;
}

String byWhom(IssueCard_Author? a) => switch (a) {
      IssueCard_Author_OnUser(:final login, :final name) =>
        '$login${name == null ? '' : ' ($name)'}',
      IssueCard_Author(:final login) => '$login (not a user)',
      null => 'ghost',
    };

String issueLine(IssueCard i) =>
    '#${i.number} ${i.title} by ${byWhom(i.author)}';

Future<void> main() async {
  final token = Platform.environment['GITHUB_TOKEN'];
  if (token == null || token.isEmpty) {
    print('SKIP GITHUB_TOKEN is not set');
    return;
  }
  final client = GraphQLClient(
    link: HttpLink('https://api.github.com/graphql',
        defaultHeaders: {'Authorization': 'bearer $token'}),
    cache: GraphQLCache(possibleTypes: possibleTypes),
    queryRequestTimeout: const Duration(seconds: 30),
  );

  final repo = await client.repoOverviewData(
      const RepoOverviewVariables(owner: 'dart-lang', name: 'sdk').toJson());
  check(repo?.nameWithOwner == 'dart-lang/sdk',
      'repository: ${repo?.nameWithOwner}');
  check((repo?.stargazerCount ?? 0) > 0, 'stars: ${repo?.stargazerCount}');
  check(repo?.primaryLanguage?.name == 'Dart',
      'primary language: ${repo?.primaryLanguage?.name}');
  final langs = repo!.languages!.edges!;
  check(langs.length == 3, 'languages(first: 3, orderBy: an input object)');
  check(repo.issues.nodes!.length == 3, 'issues with the default [OPEN]');
  for (final issue in repo.issues.nodes!) {
    print('     ${issueLine(issue!)}');
  }

  final target = repo.defaultBranchRef?.target;
  final head = switch (target) {
    RepoOverview_Repository_DefaultBranchRef_Target_OnCommit(
      :final oid,
      :final messageHeadline,
    ) =>
      'commit ${oid.value.substring(0, 7)} "$messageHeadline"',
    RepoOverview_Repository_DefaultBranchRef_Target_Other(:final typename) =>
      'other $typename',
    null => 'no target',
  };
  check(target is RepoOverview_Repository_DefaultBranchRef_Target_OnCommit,
      'interface GitObject is a Commit: $head');

  final closed = await client.repoOverviewData(const RepoOverviewVariables(
      owner: 'dart-lang',
      name: 'sdk',
      issueStates: [IssueState.CLOSED]).toJson());
  check(
      closed!.issues.totalCount != repo.issues.totalCount,
      'issueStates [CLOSED]: ${closed.issues.totalCount} '
      'vs open ${repo.issues.totalCount}');

  final search = await client.searchReposData(
      const SearchReposVariables(query: 'graphql language:dart').toJson());
  check(search.repositoryCount > 0,
      'search: ${search.repositoryCount} repositories');
  check(search.nodes!.every((n) => n is SearchRepos_Search_Nodes_OnRepository),
      'union SearchResultItem is Repository');

  final firstIssue = repo.issues.nodes!.first!;
  final node =
      await client.nodeByIdData(NodeByIdVariables(id: firstIssue.id).toJson());
  check(node is NodeById_Node_OnIssue && node.number == firstIssue.number,
      'node(id) on the interface Node is an Issue');
  if (node is NodeById_Node_OnIssue) {
    check(<IssueCard>[firstIssue, node].map(issueLine).toSet().length == 1,
        'IssueCard from two queries is the same card');
  }

  final cached = client.readIssueCardFragment({'id': firstIssue.id});
  check(cached?.title == firstIssue.title, 'readIssueCardFragment by id');
}
